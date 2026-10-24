import 'dart:convert';

import 'package:offline_engine/src/planner/errors.dart';
import 'package:offline_engine/src/planner/manifest/hls_parser.dart';
import 'package:offline_engine/src/planner/media_options.dart';
import 'package:offline_engine/src/planner/plan.dart';
import 'package:offline_engine/src/planner/sources/resolved_source.dart';
import 'package:offline_engine/src/planner/sources/source_fetcher.dart';

/// An HLS. With a master there are a quality, audios and subtitles to pick;
/// with a lone media playlist there is one track to fetch.
class HlsSource extends ResolvedSource {
  HlsSource(
    super.request, {
    required this.fetcher,
    required Uri url,
    required String text,
  }) : _master = HlsParser.isMaster(text)
           ? HlsParser.parseMaster(text, url)
           : null,
       // Read now so a live stream or DRM fails before anything is queued,
       // not once fetching starts.
       _media = HlsParser.isMaster(text)
           ? null
           : HlsParser.parseMedia(text, url) {
    _variants = _sortedVariants();
    if (_master != null && _variants.isEmpty) {
      throw const SourceException(SourceErrorCode.empty);
    }
  }

  final SourceFetcher fetcher;
  final HlsMaster? _master;

  /// The playlist received when it is not a master.
  final HlsMedia? _media;

  late final List<(String, HlsVariant)> _variants;

  @override
  SourceKind get kind => SourceKind.hls;

  /// See [ResolvedSource.onePerHeight]. The id is the position in the master.
  List<(String, HlsVariant)> _sortedVariants() {
    final master = _master;
    if (master == null) return const [];

    return [
      for (final (i, v) in ResolvedSource.onePerHeight(
        master.variants.indexed,
        height: (e) => e.$2.height,
        bandwidth: (e) => e.$2.bandwidth,
        codecs: (e) => e.$2.codecs,
      ))
        ('$i', v),
    ];
  }

  /// The id of the variant [id] resolves to, the first one when it matches
  /// none.
  String? _variantId(String? id) =>
      _variants.where((e) => e.$1 == id).firstOrNull?.$1 ??
      _variants.firstOrNull?.$1;

  HlsVariant? _variant(String? id) =>
      _variants.where((e) => e.$1 == id).firstOrNull?.$2 ??
      _variants.firstOrNull?.$2;

  @override
  List<VideoOption> get videos => [
    for (final (id, v) in _variants)
      VideoOption(
        id: id,
        width: v.width,
        height: v.height,
        bandwidth: v.bandwidth,
        codecs: v.codecs,
      ),
  ];

  @override
  List<AudioOption> audiosFor(String? videoId) {
    final master = _master;
    final variant = _variant(videoId);
    if (master == null || variant == null) return const [];

    return [
      for (final r in master.renditionsOf(
        HlsRenditionType.audio,
        variant.audioGroup,
      ))
        AudioOption(
          id: r.id,
          language: r.language,
          name: r.name,
          channels: r.channels,
          isDefault: r.isDefault,
        ),
    ];
  }

  /// Only text WebVTT subtitles are joined. Those packaged in MP4 (`wvtt`, or
  /// IMSC/TTML as `stpp`) are not offered: read as text they would break the
  /// whole download.
  static bool _textSubtitles(HlsVariant variant) {
    final codecs = variant.codecs?.toLowerCase() ?? '';
    return !codecs.contains('stpp') && !codecs.contains('wvtt');
  }

  /// Fragments that are not text WebVTT (`.m4s`, `.mp4`, `.ttml`…), in case
  /// the master does not declare its codecs.
  static bool _isTextMedia(HlsMedia media) => media.resources.every(
    (uri) => const {
      'vtt',
      'webvtt',
      'txt',
    }.contains(ResolvedSource.extensionOf(uri, fallback: 'vtt')),
  );

  @override
  List<SubtitleOption> subtitlesFor(String? videoId) {
    final master = _master;
    final variant = _variant(videoId);

    return [
      if (master != null && variant != null && _textSubtitles(variant))
        for (final r in master.renditionsOf(
          HlsRenditionType.subtitles,
          variant.subtitleGroup,
        ))
          SubtitleOption(
            id: r.id,
            language: r.language,
            name: r.name,
            forced: r.forced,
          ),
      ...externalSubtitles,
    ];
  }

  @override
  Future<DownloadPlan> plan(SourceSelection selection) async {
    final master = _master;
    final variant = _variant(selection.videoId);

    if (master == null || variant == null) {
      return DownloadPlan(
        extension: 'mkv',
        tracks: [
          _track(_media!, TrackKind.video),
          ...externalSubtitleTracks(selection),
        ],
      );
    }

    final audios = [
      for (final r in master.renditionsOf(
        HlsRenditionType.audio,
        variant.audioGroup,
      ))
        if (selection.audioIds.contains(r.id)) r,
    ];
    final subtitles = [
      if (_textSubtitles(variant))
        for (final r in master.renditionsOf(
          HlsRenditionType.subtitles,
          variant.subtitleGroup,
        ))
          if (selection.subtitleIds.contains(r.id)) r,
    ];

    // All at once: each is a small request.
    final [video, ...rest] = await Future.wait([
      _fetchMedia(variant.uri),
      for (final r in [...audios, ...subtitles]) _fetchMedia(r.uri!),
    ]);

    return DownloadPlan(
      extension: 'mkv',
      expectedBytes: variant.bandwidth * video.duration.inSeconds ~/ 8,
      tracks: [
        _track(
          video,
          TrackKind.video,
          codecs: variant.codecs,
          sourceId: _variantId(selection.videoId),
        ),
        for (final (i, r) in audios.indexed)
          _track(
            rest[i],
            TrackKind.audio,
            language: r.language,
            label: r.name,
            sourceId: r.id,
          ),
        for (final (i, r) in subtitles.indexed)
          if (_isTextMedia(rest[audios.length + i]))
            _subtitleTrack(rest[audios.length + i], r),
        ...externalSubtitleTracks(selection),
      ],
    );
  }

  Future<HlsMedia> _fetchMedia(Uri url) async {
    final response = await fetcher.fetch(
      url,
      headers: request.headers ?? const {},
    );
    return HlsParser.parseMedia(
      utf8.decode(response.body, allowMalformed: true),
      response.url,
    );
  }

  /// Every resource is saved under its position, and the local playlist
  /// points at those names.
  PlannedTrack _track(
    HlsMedia media,
    TrackKind kind, {
    String? language,
    String? label,
    String? codecs,
    String? sourceId,
  }) {
    final names = _names(media, fallback: 'bin');
    return PlannedTrack(
      kind: kind,
      assembly: TrackAssembly.hlsPlaylist,
      pieces: [
        for (final uri in media.resources)
          PlannedPiece(url: uri.toString(), file: names[uri]!),
      ],
      playlist: media.localPlaylist(names),
      language: language,
      label: label,
      codecs: codecs,
      sourceId: sourceId,
    );
  }

  PlannedTrack _subtitleTrack(HlsMedia media, HlsRendition rendition) {
    final names = _names(media, fallback: 'vtt');
    return PlannedTrack(
      kind: TrackKind.subtitle,
      assembly: media.resources.length == 1
          ? TrackAssembly.single
          : TrackAssembly.vttSegments,
      pieces: [
        for (final uri in media.resources)
          PlannedPiece(url: uri.toString(), file: names[uri]!),
      ],
      language: rendition.language,
      label: rendition.name,
      forced: rendition.forced,
      sourceId: rendition.id,
    );
  }

  static Map<Uri, String> _names(HlsMedia media, {required String fallback}) =>
      {
        for (final (i, uri) in media.resources.indexed)
          uri: '$i.${ResolvedSource.extensionOf(uri, fallback: fallback)}',
      };
}
