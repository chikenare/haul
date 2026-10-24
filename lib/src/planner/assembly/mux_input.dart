import 'package:haul/src/planner/plan.dart';

/// A track ready for ffmpeg.
class MuxInput {
  const MuxInput({
    required this.path,
    required this.kind,
    this.language,
    this.label,
    this.forced = false,
    this.isHlsPlaylist = false,
  });

  final String path;
  final TrackKind kind;

  /// BCP-47.
  final String? language;
  final String? label;
  final bool forced;

  /// A local playlist: ffmpeg needs leave to open its fragments and keys.
  final bool isHlsPlaylist;

  /// The input options and the `-i`.
  List<String> get ffmpegArgs => [
    if (isHlsPlaylist) ...[
      '-allowed_extensions', 'ALL', //
      '-extension_picky', '0',
      '-protocol_whitelist', 'file,crypto,data',
    ],
    '-i',
    path,
  ];
}
