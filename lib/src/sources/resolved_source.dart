import 'dart:math';

import 'package:media_downloader/src/language_codes.dart';
import 'package:media_downloader/src/media_options.dart';
import 'package:media_downloader/src/plan.dart';
import 'package:media_downloader/src/sources/source_request.dart';
import 'package:media_downloader/src/track_criteria.dart';
import 'package:path/path.dart' as p;

/// A source already inspected: what it offers (qualities, audios, subtitles)
/// and how to turn what was picked into a [DownloadPlan].
///
/// The request's external subtitles apply to any kind of source, so they are
/// resolved here; each subclass adds its own.
abstract class ResolvedSource {
  ResolvedSource(this.request);

  final SourceRequest request;

  SourceKind get kind;

  /// Empty when there are no qualities to choose from.
  List<VideoOption> get videos => const [];

  List<AudioOption> audiosFor(String? videoId) => const [];

  List<SubtitleOption> subtitlesFor(String? videoId) => externalSubtitles;

  /// The best quality and every track: an MKV holds several audios and
  /// subtitles, which is exactly what a single file loses.
  SourceSelection get defaultSelection => selectionFor(const TrackCriteria());

  /// What [criteria] picks. With [videoId], that quality and the tracks that
  /// go with it.
  SourceSelection selectionFor(TrackCriteria criteria, {String? videoId}) {
    final video = videoId ?? _videoFor(criteria.maxHeight);
    final audios = audiosFor(video);
    var pickedAudios = _pick(audios, criteria.audio);
    // No audio is no film: without the language, the one the manifest marks
    // as default, or the first.
    if (pickedAudios.isEmpty && audios.isNotEmpty) {
      pickedAudios = [
        audios.where((a) => a.isDefault).firstOrNull ?? audios.first,
      ];
    }

    return SourceSelection(
      videoId: video,
      audioIds: {for (final a in pickedAudios) a.id},
      subtitleIds: {
        for (final s in _pick(subtitlesFor(video), criteria.subtitles)) s.id,
      },
    );
  }

  /// Whether [criteria] leaves the audio to a person: some language has
  /// several equally good tracks (`es` with a Latin American and a Castilian
  /// one) or none of the wanted ones exists. When only some are missing, what
  /// there is gets downloaded; with a single track there is nothing to
  /// choose. Subtitles never ask: they weigh little and every match is kept.
  ///
  /// Only for an app that receives downloads from outside and can show a
  /// sheet; an app deciding from its own account preferences ignores it and
  /// takes [selectionFor] as it is.
  bool needsChoice(TrackCriteria criteria) {
    if (criteria.audio case LanguageTracks(:final languages)) {
      final audios = audiosFor(_videoFor(criteria.maxHeight));
      if (audios.length <= 1) return false;
      final matches = [
        for (final language in languages) _closest(audios, language).length,
      ];
      return matches.any((n) => n > 1) || matches.every((n) => n == 0);
    }
    return false;
  }

  /// The declared language or the label's (external subtitles carry only a
  /// label), with the variant when either says it.
  static String? _languageOf(Object track) => switch (track) {
    AudioOption(:final language, :final name) => trackLanguage(language, name),
    SubtitleOption(:final language, :final name) => trackLanguage(
      language,
      name,
    ),
    _ => null,
  };

  /// [videos] runs highest first: the first not above [maxHeight], or the
  /// lowest when all are. A video that declares no height cannot be compared
  /// and only comes out when there is nothing else.
  String? _videoFor(int? maxHeight) {
    if (maxHeight == null) return videos.firstOrNull?.id;

    final measured = videos.where((v) => v.height != null).toList();
    if (measured.isEmpty) return videos.firstOrNull?.id;
    return (measured.where((v) => v.height! <= maxHeight).firstOrNull ??
            measured.last)
        .id;
  }

  /// All, none or, per language, the closest ones, in manifest order.
  static List<T> _pick<T extends Object>(
    List<T> tracks,
    TrackPreference preference,
  ) {
    switch (preference) {
      case AllTracks():
        return tracks;
      case NoTracks():
        return const [];
      case LanguageTracks(:final languages):
        final picked = {
          for (final language in languages) ..._closest(tracks, language),
        };
        return [
          for (final t in tracks)
            if (picked.contains(t)) t,
        ];
    }
  }

  /// The tracks closest to [language]: with `es-419`, the Latin American
  /// ones when there are any, otherwise any Spanish.
  static List<T> _closest<T extends Object>(List<T> tracks, String language) {
    final scores = [
      for (final t in tracks) languageMatch(_languageOf(t), language),
    ];
    final best = scores.fold(0, max);
    if (best == 0) return const [];
    return [
      for (final (i, t) in tracks.indexed)
        if (scores[i] == best) t,
    ];
  }

  /// Estimated weight of [selection], or null when it is not known up front.
  int? estimatedBytes(SourceSelection selection) => null;

  /// May hit the network (HLS media playlists, for one).
  Future<DownloadPlan> plan(SourceSelection selection);

  static const _externalPrefix = 'ext:';

  List<SubtitleOption> get externalSubtitles => [
    for (final label in (request.subtitles ?? const {}).keys)
      SubtitleOption(id: '$_externalPrefix$label', name: label),
  ];

  List<PlannedTrack> externalSubtitleTracks(SourceSelection selection) => [
    for (final MapEntry(key: label, value: url)
        in (request.subtitles ?? const <String, String>{}).entries)
      if (selection.subtitleIds.contains('$_externalPrefix$label'))
        singleTrack(
          TrackKind.subtitle,
          Uri.parse(url),
          'vtt',
          label: label,
          sourceId: '$_externalPrefix$label',
        ),
  ];

  /// A track that is one file.
  static PlannedTrack singleTrack(
    TrackKind kind,
    Uri url,
    String fallbackExtension, {
    String? language,
    String? label,
    bool forced = false,
    String? sourceId,
  }) {
    return PlannedTrack(
      kind: kind,
      assembly: TrackAssembly.single,
      pieces: [
        PlannedPiece(
          url: url.toString(),
          file: '0.${extensionOf(url, fallback: fallbackExtension)}',
        ),
      ],
      language: language,
      label: label,
      forced: forced,
      sourceId: sourceId,
    );
  }

  /// One quality per height, highest first. Manifests repeat a height across
  /// codecs and audio groups, and to whoever picks they are the same option:
  /// the one any phone plays wins (H.264 video, AAC audio — AC-3 and E-AC-3
  /// depend on the device's decoder) and, between equals, the higher
  /// bitrate. What declares no height is offered as it is, by bitrate.
  static List<T> onePerHeight<T>(
    Iterable<T> items, {
    required int? Function(T) height,
    required int? Function(T) bandwidth,
    required String? Function(T) codecs,
  }) {
    int compatibility(T item) {
      final value = codecs(item)?.toLowerCase() ?? '';
      final avc = value.contains('avc') ? 2 : 0;
      final surround = value.contains('ac-3') || value.contains('ec-3');
      return avc + (surround ? 0 : 1);
    }

    final sorted = items.toList()
      ..sort((a, b) {
        final byHeight = (height(b) ?? 0).compareTo(height(a) ?? 0);
        if (byHeight != 0) return byHeight;
        final byCompatibility = compatibility(b).compareTo(compatibility(a));
        if (byCompatibility != 0) return byCompatibility;
        return (bandwidth(b) ?? 0).compareTo(bandwidth(a) ?? 0);
      });

    final seen = <Object>{};
    return [
      for (final item in sorted)
        if (seen.add(height(item) ?? 'bw${bandwidth(item)}')) item,
    ];
  }

  /// The extension of [url]'s path when it looks like one (short and
  /// alphanumeric); otherwise [fallback]. Signed links rarely carry one.
  static String extensionOf(Uri url, {required String fallback}) {
    final ext = p.url.extension(url.path).replaceFirst('.', '').toLowerCase();
    return _extension.hasMatch(ext) ? ext : fallback;
  }

  static final _extension = RegExp(r'^[a-z0-9]{1,5}$');
}
