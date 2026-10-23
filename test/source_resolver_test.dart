import 'dart:convert';

import 'package:media_planner/media_planner.dart';
import 'package:test/test.dart';

/// Responde desde un mapa de URL → (cabeceras, cuerpo) y anota las peticiones.
class _FakeFetcher extends SourceFetcher {
  _FakeFetcher(this.routes);

  final Map<String, (Map<String, String>, String)> routes;
  final requested = <String>[];

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    requested.add(url.toString());
    final route = routes[url.toString()];
    if (route == null) throw SourceException(SourceErrorCode.http(404));

    final body = utf8.encode(route.$2);
    final truncated = maxBytes != null && body.length > maxBytes;
    return FetchedResponse(
      url: url,
      headers: route.$1,
      body: truncated ? body.sublist(0, maxBytes) : body,
      truncated: truncated,
    );
  }
}

void main() {
  test('a signed link without extension is sniffed as a file', () async {
    final fetcher = _FakeFetcher({
      'https://cdn.example.com/dl/abc': (
        {
          'content-type': 'application/octet-stream',
          'content-length': '734003200',
          'content-disposition': 'attachment; filename="Movie (2020).mkv"',
        },
        '\x1aE\xdf\xa3 binary',
      ),
    });

    final source = await SourceResolver(
      fetcher: fetcher,
    ).resolve(const SourceRequest(url: 'https://cdn.example.com/dl/abc'));

    expect(source, isA<FileSource>());
    final file = source as FileSource;
    expect(file.extension, 'mkv');
    expect(source.estimatedBytes(source.defaultSelection), 734003200);

    final plan = await source.plan(source.defaultSelection);
    expect(plan.needsMux, isFalse);
    expect(plan.extension, 'mkv');
    expect(plan.tracks.single.pieces.single.file, '0.mkv');
  });

  test('external subtitles turn a direct file into an MKV', () async {
    final fetcher = _FakeFetcher({
      'https://cdn.example.com/movie.mp4': (
        {'content-type': 'video/mp4'},
        '....ftyp',
      ),
    });
    final source = await SourceResolver(fetcher: fetcher).resolve(
      const SourceRequest(
        url: 'https://cdn.example.com/movie.mp4',
        subtitles: {'Español': 'https://subs.example.com/es.srt'},
      ),
    );

    final plan = await source.plan(source.defaultSelection);
    expect(plan.needsMux, isTrue);
    expect(plan.extension, 'mkv');
    expect(plan.tracks.map((t) => t.kind), [
      TrackKind.video,
      TrackKind.subtitle,
    ]);
    expect(plan.tracks.last.pieces.single.file, '0.srt');
  });

  test('HLS master: picks the best variant and plans its renditions', () async {
    const master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="es",NAME="Español",URI="es.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="en",NAME="English",URI="en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,AUDIO="a"
360.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,AUDIO="a"
1080.m3u8
''';
    String media(String name) =>
        '#EXTM3U\n#EXTINF:5,\n$name-0.ts\n#EXTINF:5,\n$name-1.ts\n#EXT-X-ENDLIST\n';

    const base = 'https://cdn.example.com/hls';
    final fetcher = _FakeFetcher({
      '$base/master': (
        {'content-type': 'application/vnd.apple.mpegurl'},
        master,
      ),
      '$base/1080.m3u8': (const {}, media('v')),
      '$base/es.m3u8': (const {}, media('es')),
      '$base/en.m3u8': (const {}, media('en')),
    });

    final source = await SourceResolver(
      fetcher: fetcher,
    ).resolve(const SourceRequest(url: '$base/master'));
    expect(source, isA<HlsSource>());
    expect(source.videos.map((v) => v.label), ['1080p', '360p']);

    final selection = source.defaultSelection;
    expect(selection.audioIds, hasLength(2));

    final plan = await source.plan(
      selection.copyWith(
        audioIds: {source.audiosFor(selection.videoId).last.id},
      ),
    );
    expect(fetcher.requested, isNot(contains('$base/es.m3u8')));
    expect(plan.tracks.map((t) => t.kind), [TrackKind.video, TrackKind.audio]);
    expect(plan.tracks.last.language, 'en');
    expect(plan.pieceCount, 4);
    expect(plan.isSegmented, isTrue);
    expect(plan.expectedBytes, 4000000 * 10 ~/ 8);
    expect(plan.tracks.first.playlist, contains('\n0.ts\n'));
    expect(plan.tracks.first.pieces.first.url, '$base/v-0.ts');
  });

  test(
    'DASH: hides protected video and fails when nothing else is left',
    () async {
      const mpd =
          '''<?xml version="1.0"?><MPD type="static" mediaPresentationDuration="PT8S"><Period>
  <AdaptationSet mimeType="video/mp4"><ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011"/>
    <Representation id="v" bandwidth="1"><BaseURL>v.mp4</BaseURL></Representation>
  </AdaptationSet></Period></MPD>''';
      final fetcher = _FakeFetcher({
        'https://cdn.example.com/a.mpd': (
          {'content-type': 'application/dash+xml'},
          mpd,
        ),
      });

      expect(
        () => SourceResolver(
          fetcher: fetcher,
        ).resolve(const SourceRequest(url: 'https://cdn.example.com/a.mpd')),
        throwsA(
          isA<SourceException>().having(
            (e) => e.code,
            'code',
            SourceErrorCode.drm,
          ),
        ),
      );
    },
  );

  test(
    'DASH: plans concatenated video and audio with a size estimate',
    () async {
      const mpd =
          '''<MPD type="static" mediaPresentationDuration="PT8S"><Period>
  <AdaptationSet mimeType="video/mp4"><SegmentTemplate timescale="1" duration="4" initialization="\$RepresentationID\$-i.mp4" media="\$RepresentationID\$-\$Number\$.m4s"/>
    <Representation id="hd" bandwidth="2000" height="720"/><Representation id="sd" bandwidth="1000" height="480"/>
  </AdaptationSet>
  <AdaptationSet mimeType="audio/mp4" lang="es"><SegmentTemplate timescale="1" duration="4" initialization="a-i.mp4" media="a-\$Number\$.m4s"/>
    <Representation id="a" bandwidth="1000"/>
  </AdaptationSet></Period></MPD>''';
      final fetcher = _FakeFetcher({
        'https://cdn.example.com/m': (const {}, mpd),
      });

      final source = await SourceResolver(
        fetcher: fetcher,
      ).resolve(const SourceRequest(url: 'https://cdn.example.com/m'));
      expect(source, isA<DashSource>());

      final selection = source.defaultSelection;
      expect(selection.videoId, 'hd');
      expect(source.estimatedBytes(selection), (2000 + 1000) * 8 ~/ 8);

      final plan = await source.plan(selection);
      expect(plan.tracks.map((t) => t.assembly), [
        TrackAssembly.concat,
        TrackAssembly.concat,
      ]);
      expect(plan.tracks.first.pieces.map((p) => p.file), [
        '0.mp4',
        '1.mp4',
        '2.mp4',
      ]);
      expect(plan.tracks.last.language, 'es');
    },
  );

  test('one quality per resolution, preferring H.264 with AAC', () async {
    const master = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080,CODECS="hvc1.2.4.L123.B0"
hevc1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=7000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
avc1080lo.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=7500000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
avc1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=7900000,RESOLUTION=1920x1080,CODECS="avc1.640028,ac-3"
avc1080ac3.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="hvc1.2.4.L93.B0"
hevc720.m3u8
''';
    final fetcher = _FakeFetcher({'https://a/m.m3u8': (const {}, master)});
    final source = await SourceResolver(
      fetcher: fetcher,
    ).resolve(const SourceRequest(url: 'https://a/m.m3u8'));

    expect(source.videos.map((v) => v.label), ['1080p', '720p · HEVC']);
    expect(source.videos.first.bandwidth, 7500000);
  });

  test('un filename con % literal no rompe la resolución', () {
    final response = FetchedResponse(
      url: Uri.parse('https://a/x'),
      headers: const {
        'content-disposition': 'attachment; filename="100% Movie.mp4"',
      },
      body: const [],
      truncated: false,
    );
    expect(response.suggestedFilename, '100% Movie.mp4');

    final encoded = FetchedResponse(
      url: Uri.parse('https://a/x'),
      headers: const {
        'content-disposition': "attachment; filename*=UTF-8''Pel%C3%ADcula.mkv",
      },
      body: const [],
      truncated: false,
    );
    expect(encoded.suggestedFilename, 'Película.mkv');
  });

  test('el contenido manda sobre una extensión equivocada', () {
    final mkv = [0x1A, 0x45, 0xDF, 0xA3, ...'....matroska'.codeUnits];
    final response = FetchedResponse(
      url: Uri.parse('https://cdn/v/movie.mp4'),
      headers: const {'content-type': 'video/mp4'},
      body: mkv,
      truncated: true,
    );
    expect(
      FileSource(const SourceRequest(url: 'u'), response).extension,
      'mkv',
    );
    expect(
      FileSource.sniffContainer([0, 0, 0, 0x18, ...'ftypisom'.codeUnits]),
      contains('mp4'),
    );
    expect(FileSource.sniffContainer('Gnothing'.codeUnits), isNull);
  });

  test('un MPD con prefijo de espacio de nombres se reconoce', () async {
    const mpd =
        '<?xml version="1.0"?><mpd:MPD xmlns:mpd="urn:mpeg:dash:schema:mpd:2011" '
        'type="static" mediaPresentationDuration="PT4S"><mpd:Period>'
        '<mpd:AdaptationSet mimeType="video/mp4"><mpd:Representation id="v" bandwidth="1">'
        '<mpd:BaseURL>v.mp4</mpd:BaseURL></mpd:Representation></mpd:AdaptationSet>'
        '</mpd:Period></mpd:MPD>';
    final source = await SourceResolver(
      fetcher: _FakeFetcher({'https://a/m': (const {}, mpd)}),
    ).resolve(const SourceRequest(url: 'https://a/m'));
    expect(source, isA<DashSource>());
  });
}
