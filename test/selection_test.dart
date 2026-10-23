import 'package:media_planner/media_planner.dart';
import 'package:test/test.dart';

/// Una fuente con calidades y pistas fijas, para probar qué se marca.
class _Source extends ResolvedSource {
  _Source({
    this.videos = const [],
    this.audios = const [],
    this.subtitles = const [],
    Map<String, String>? external,
  }) : super(SourceRequest(url: 'u', subtitles: external));

  @override
  final List<VideoOption> videos;
  final List<AudioOption> audios;
  final List<SubtitleOption> subtitles;

  @override
  SourceKind get kind => SourceKind.hls;

  @override
  List<AudioOption> audiosFor(String? videoId) => audios;

  @override
  List<SubtitleOption> subtitlesFor(String? videoId) => [
    ...subtitles,
    ...externalSubtitles,
  ];

  @override
  Future<DownloadPlan> plan(SourceSelection selection) =>
      throw UnimplementedError();
}

void main() {
  const videos = [
    VideoOption(id: '1080', height: 1080),
    VideoOption(id: '720', height: 720),
    VideoOption(id: '360', height: 360),
  ];

  group('calidad', () {
    final source = _Source(videos: videos);
    String? pick(int? maxHeight) =>
        source.selectionFor(TrackCriteria(maxHeight: maxHeight)).videoId;

    test('la mejor, o la mejor que no pase del tope', () {
      expect(pick(null), '1080');
      expect(pick(1080), '1080');
      expect(pick(720), '720');
      expect(pick(480), '360');
    });

    test('si todas pasan del tope, la más baja', () {
      final hd = _Source(videos: videos.take(2).toList());
      expect(
        hd.selectionFor(const TrackCriteria(maxHeight: 480)).videoId,
        '720',
      );
    });

    test('sin alturas declaradas, la primera', () {
      final unknown = _Source(
        videos: const [
          VideoOption(id: 'a', bandwidth: 5000),
          VideoOption(id: 'b', bandwidth: 1000),
        ],
      );
      expect(
        unknown.selectionFor(const TrackCriteria(maxHeight: 480)).videoId,
        'a',
      );
    });
  });

  group('audio', () {
    const audios = [
      AudioOption(id: 'en', language: 'en', isDefault: true),
      AudioOption(id: 'es', language: 'es-419'),
      AudioOption(id: 'ja', name: '日本語'),
    ];
    final source = _Source(videos: videos, audios: audios);
    Set<String> pick(TrackPreference p) =>
        source.selectionFor(TrackCriteria(audio: p)).audioIds;

    test('todos, o los del idioma (por código o por nombre)', () {
      expect(pick(const AllTracks()), {'en', 'es', 'ja'});
      expect(pick(const LanguageTracks(['es'])), {'es'});
      expect(pick(const LanguageTracks(['ja'])), {'ja'});
    });

    test('si no está el idioma, el de por defecto: nunca sin audio', () {
      expect(pick(const LanguageTracks(['fr'])), {'en'});
      expect(pick(const NoTracks()), {'en'});
    });
  });

  group('subtítulos', () {
    final source = _Source(
      videos: videos,
      subtitles: const [
        SubtitleOption(id: 'es', language: 'spa'),
        SubtitleOption(id: 'es-f', language: 'es', forced: true),
        SubtitleOption(id: 'en', language: 'en'),
      ],
      external: {'Español (Latino)': 'https://s/es.vtt', 'Other': 'x'},
    );
    Set<String> pick(TrackPreference p) =>
        source.selectionFor(TrackCriteria(subtitles: p)).subtitleIds;

    test('todos, ninguno o los del idioma, incluidos los externos', () {
      expect(pick(const AllTracks()), hasLength(5));
      expect(pick(const NoTracks()), isEmpty);
      expect(pick(const LanguageTracks(['es'])), {
        'es',
        'es-f',
        'ext:Español (Latino)',
      });
      expect(pick(const LanguageTracks(['fr'])), isEmpty);
    });
  });

  test('cambiar de calidad en la hoja mantiene las preferencias', () {
    final source = _Source(
      videos: videos,
      audios: const [
        AudioOption(id: 'en', language: 'en'),
        AudioOption(id: 'es', language: 'es'),
      ],
    );
    final selection = source.selectionFor(
      const TrackCriteria(audio: LanguageTracks(['es'])),
      videoId: '360',
    );
    expect(selection.videoId, '360');
    expect(selection.audioIds, {'es'});
  });

  test('preferencias guardadas: ida y vuelta', () {
    for (final p in const [
      AllTracks(),
      NoTracks(),
      LanguageTracks(['pt']),
      LanguageTracks(['es-419', 'en']),
    ]) {
      expect(TrackPreference.parse(p.encode()), p);
    }
    expect(TrackPreference.parse(null), const AllTracks());
    expect(TrackPreference.parse('basura'), const AllTracks());
  });

  test('idioma por etiqueta', () {
    expect(languageOfLabel('Español (Latinoamérica)'), 'es-419');
    expect(languageOfLabel('Castellano'), 'es-ES');
    expect(languageOfLabel('Portuguese (Brazil)'), 'pt-BR');
    expect(languageOfLabel('Español'), 'es');
    expect(languageOfLabel('English SDH'), 'en');
    expect(languageOfLabel('Spanish'), 'es');
    expect(languageOfLabel('Forzados'), isNull);
    expect(sameLanguage('es-419', 'spa'), isTrue);
    expect(sameLanguage('und', 'und'), isFalse);
  });

  group('preferencias de la app emisora', () {
    const dual = [
      AudioOption(id: 'lat', language: 'es', name: 'Español (Latino)'),
      AudioOption(id: 'cas', language: 'es-ES', name: 'Español'),
      AudioOption(id: 'en', language: 'en', isDefault: true),
    ];
    final source = _Source(videos: videos, audios: dual);
    // What an app sends or an account stores: tags, `none` or `all`.
    TrackCriteria criteria({
      List<String>? audio,
      List<String>? subtitles,
      int? quality,
    }) => TrackCriteria(
      maxHeight: quality,
      audio: TrackPreference.fromTags(audio) ?? const AllTracks(),
      subtitles: TrackPreference.fromTags(subtitles) ?? const AllTracks(),
    );

    test('con región elige esa variante sin preguntar', () {
      final c = criteria(audio: ['es-419']);
      expect(source.needsChoice(c), isFalse);
      expect(source.selectionFor(c).audioIds, {'lat'});

      final mx = criteria(audio: ['es-MX']);
      expect(source.selectionFor(mx).audioIds, {'lat'});
      expect(source.selectionFor(criteria(audio: ['es-ES'])).audioIds, {'cas'});
    });

    test('sin región y con varias del idioma, pregunta', () {
      final c = criteria(audio: ['es']);
      expect(source.needsChoice(c), isTrue);
      expect(source.selectionFor(c).audioIds, {'lat', 'cas'});
    });

    test('sin región y con una sola del idioma, no pregunta', () {
      final single = _Source(
        videos: videos,
        audios: const [
          AudioOption(id: 'es', language: 'es'),
          AudioOption(id: 'en', language: 'en'),
        ],
      );
      final c = criteria(audio: ['es']);
      expect(single.needsChoice(c), isFalse);
      expect(single.selectionFor(c).audioIds, {'es'});
    });

    test('la variante pedida no está: cualquiera del idioma', () {
      final castellano = _Source(
        videos: videos,
        audios: const [
          AudioOption(id: 'cas', language: 'es-ES'),
          AudioOption(id: 'en', language: 'en'),
        ],
      );
      final c = criteria(audio: ['es-419']);
      expect(castellano.needsChoice(c), isFalse);
      expect(castellano.selectionFor(c).audioIds, {'cas'});
    });

    test('el idioma no está y hay varios audios: pregunta', () {
      final c = criteria(audio: ['fr-FR']);
      expect(source.needsChoice(c), isTrue);
      expect(source.selectionFor(c).audioIds, {'en'});
    });

    test('con un solo audio nunca pregunta', () {
      final one = _Source(
        videos: videos,
        audios: const [AudioOption(id: 'en', language: 'en')],
      );
      expect(one.needsChoice(criteria(audio: ['fr'])), isFalse);
      expect(_Source().needsChoice(criteria()), isFalse);
    });

    test('calidad exacta y subtítulos de la variante', () {
      final withSubs = _Source(
        videos: const [
          VideoOption(id: '1080', height: 1080),
          VideoOption(id: '576', height: 576),
          VideoOption(id: '360', height: 360),
        ],
        subtitles: const [
          SubtitleOption(id: 'lat', language: 'es-419'),
          SubtitleOption(id: 'lat-f', language: 'es-419', forced: true),
          SubtitleOption(id: 'cas', language: 'es-ES'),
        ],
      );
      final c = criteria(subtitles: ['es-419'], quality: 576);
      final selection = withSubs.selectionFor(c);
      expect(selection.videoId, '576');
      expect(selection.subtitleIds, {'lat', 'lat-f'});
      expect(
        withSubs.selectionFor(criteria(subtitles: ['none'])).subtitleIds,
        isEmpty,
      );
    });

    test('varios idiomas: cada uno por separado', () {
      final c = criteria(audio: ['es-419', 'en-US']);
      expect(source.needsChoice(c), isFalse);
      expect(source.selectionFor(c).audioIds, {'lat', 'en'});
    });

    test('varios idiomas: si falta uno, se baja lo que hay', () {
      final c = criteria(audio: ['es-419', 'fr']);
      expect(source.needsChoice(c), isFalse);
      expect(source.selectionFor(c).audioIds, {'lat'});
    });

    test('varios idiomas: uno ambiguo, o ninguno encontrado, pregunta', () {
      expect(source.needsChoice(criteria(audio: ['es', 'en'])), isTrue);
      expect(source.needsChoice(criteria(audio: ['fr', 'de'])), isTrue);
    });

    test('las etiquetas se leen como lista, none o all', () {
      expect(TrackPreference.fromTags(['none']), const NoTracks());
      expect(TrackPreference.fromTags(['es', 'all']), const AllTracks());
    });
  });
}
