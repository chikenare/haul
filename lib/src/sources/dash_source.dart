import 'package:media_planner/src/errors.dart';
import 'package:media_planner/src/manifest/dash_parser.dart';
import 'package:media_planner/src/media_options.dart';
import 'package:media_planner/src/plan.dart';
import 'package:media_planner/src/sources/resolved_source.dart';

/// A DASH without DRM: every picked representation is fetched (init +
/// fragments) and read as one track when packaged or merged.
class DashSource extends ResolvedSource {
  DashSource(super.request, DashManifest manifest)
    : _duration = manifest.duration,
      _videos = ResolvedSource.onePerHeight(
        manifest.ofType(DashContentType.video).where((r) => !r.isProtected),
        height: (r) => r.height,
        bandwidth: (r) => r.bandwidth,
        codecs: (r) => r.codecs,
      ),
      _audios = _bestPerSet(manifest.ofType(DashContentType.audio)),
      _subtitles = [
        for (final r in manifest.ofType(DashContentType.text))
          // Only WebVTT in one file: subtitles fragmented in MP4 (wvtt/stpp)
          // cannot be joined as text.
          if (!r.isProtected &&
              r.mimeType == 'text/vtt' &&
              r.resources.length == 1)
            r,
      ] {
    if (_videos.isEmpty) {
      // There was video but all of it encrypted: DRM, not an empty MPD.
      final protected = manifest.ofType(DashContentType.video).isNotEmpty;
      throw SourceException(
        protected ? SourceErrorCode.drm : SourceErrorCode.empty,
      );
    }
  }

  final Duration _duration;
  final List<DashRepresentation> _videos;
  final List<DashRepresentation> _audios;
  final List<DashRepresentation> _subtitles;

  @override
  SourceKind get kind => SourceKind.dash;

  /// Without the encrypted ones, highest bitrate first.
  static List<DashRepresentation> _sorted(Iterable<DashRepresentation> reps) {
    return reps.where((r) => !r.isProtected).toList()..sort((a, b) {
      final byHeight = (b.height ?? 0).compareTo(a.height ?? 0);
      return byHeight != 0
          ? byHeight
          : (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
    });
  }

  /// Every audio AdaptationSet is a language or variant; within it only the
  /// best quality is offered.
  static List<DashRepresentation> _bestPerSet(
    Iterable<DashRepresentation> reps,
  ) {
    final best = <int, DashRepresentation>{};
    for (final r in _sorted(reps)) {
      final current = best[r.adaptationSet];
      if (current == null || (r.bandwidth ?? 0) > (current.bandwidth ?? 0)) {
        best[r.adaptationSet] = r;
      }
    }
    return best.values.toList();
  }

  DashRepresentation _video(String? id) =>
      _videos.where((r) => r.id == id).firstOrNull ?? _videos.first;

  @override
  List<VideoOption> get videos => [
    for (final r in _videos)
      VideoOption(
        id: r.id,
        width: r.width,
        height: r.height,
        bandwidth: r.bandwidth,
        codecs: r.codecs,
      ),
  ];

  @override
  List<AudioOption> audiosFor(String? videoId) => [
    for (final r in _audios)
      AudioOption(
        id: r.id,
        language: r.language,
        name: r.label,
        bandwidth: r.bandwidth,
        isDefault: r.isMainAudio,
      ),
  ];

  @override
  List<SubtitleOption> subtitlesFor(String? videoId) => [
    for (final r in _subtitles)
      SubtitleOption(
        id: r.id,
        language: r.language,
        name: r.label,
        forced: r.forced,
      ),
    ...externalSubtitles,
  ];

  @override
  int? estimatedBytes(SourceSelection selection) {
    final bandwidth = [
      _video(selection.videoId),
      ..._audios.where((r) => selection.audioIds.contains(r.id)),
    ].fold<int>(0, (sum, r) => sum + (r.bandwidth ?? 0));

    if (bandwidth == 0 || _duration == Duration.zero) return null;
    return bandwidth * _duration.inSeconds ~/ 8;
  }

  @override
  Future<DownloadPlan> plan(SourceSelection selection) async {
    return DownloadPlan(
      extension: 'mkv',
      expectedBytes: estimatedBytes(selection) ?? 0,
      tracks: [
        _track(_video(selection.videoId), TrackKind.video),
        for (final r in _audios)
          if (selection.audioIds.contains(r.id)) _track(r, TrackKind.audio),
        for (final r in _subtitles)
          if (selection.subtitleIds.contains(r.id))
            _track(r, TrackKind.subtitle),
        ...externalSubtitleTracks(selection),
      ],
    );
  }

  PlannedTrack _track(DashRepresentation rep, TrackKind kind) {
    final extension = switch (rep.mimeType?.split('/').last) {
      'webm' => 'webm',
      'vtt' => 'vtt',
      _ => 'mp4',
    };

    return PlannedTrack(
      kind: kind,
      assembly: rep.resources.length == 1
          ? TrackAssembly.single
          : TrackAssembly.concat,
      pieces: [
        for (final (i, segment) in rep.segments.indexed)
          PlannedPiece(
            url: segment.uri.toString(),
            file: '$i.$extension',
            duration: segment.seconds,
          ),
      ],
      language: rep.language,
      label: rep.label,
      forced: rep.forced,
      codecs: rep.codecs,
      sourceId: rep.id,
    );
  }
}
