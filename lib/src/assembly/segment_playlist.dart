import 'dart:math';

import 'package:media_planner/src/plan.dart';

/// An MP4 DASH track as an HLS media playlist: its fragments as they are,
/// with the init as `EXT-X-MAP`. The player (local package) and ffmpeg (when
/// merging) open it without first joining the fragments into a file, which
/// would be one whole extra copy.
extension SegmentPlaylist on PlannedTrack {
  /// Whether it can be written: everything in MP4 (WebM does not fit in an
  /// HLS) and every fragment with its duration.
  bool get hasSegmentPlaylist =>
      pieces.every((piece) => piece.file.endsWith('.mp4')) &&
      _segments.isNotEmpty &&
      _segments.every((piece) => piece.duration != null);

  String get segmentPlaylist {
    final target = _segments.map((s) => s.duration!).fold(0.0, max).ceil();
    return [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-PLAYLIST-TYPE:VOD',
      '#EXT-X-TARGETDURATION:${max(target, 1)}',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      if (_hasInit) '#EXT-X-MAP:URI="${pieces.first.file}"',
      for (final segment in _segments) ...[
        '#EXTINF:${segment.duration!.toStringAsFixed(3)},',
        segment.file,
      ],
      '#EXT-X-ENDLIST',
      '',
    ].join('\n');
  }

  /// The fragments, without the init.
  List<PlannedPiece> get _segments => _hasInit ? pieces.sublist(1) : pieces;

  bool get _hasInit => pieces.length > 1 && pieces.first.duration == null;
}
