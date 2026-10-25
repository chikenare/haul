import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/ffmpeg/ffmpeg_kit_runner.dart';
import 'package:haul/src/planner/assembly/mux_input.dart';

/// Takes one frame of a video as its thumbnail, for downloads that come
/// without a picture.
class FrameGrabber {
  const FrameGrabber();

  /// A minute in first — openings are often black or a logo — and from the
  /// start when the video is shorter.
  static const _offsets = [Duration(seconds: 60), Duration.zero];

  /// Writes a JPEG to [outputPath] and answers whether it could; a
  /// thumbnail never fails a download. [video] may be a `content://` URI.
  Future<bool> grab(MuxInput video, String outputPath) async {
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await quietFfmpeg();

    for (final offset in _offsets) {
      final input = await _readable(video);
      if (input == null) return false;
      final session = await FFmpegKit.executeWithArguments(
        buildArgs(input, outputPath, offset),
      );
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await output.exists() &&
          await output.length() > 0) {
        return true;
      }
    }
    if (await output.exists()) await output.delete();
    return false;
  }

  /// A URI is opened through an ffmpeg-kit `saf:` parameter, good for one
  /// run only: a new one per attempt.
  static Future<MuxInput?> _readable(MuxInput video) async {
    if (!video.path.startsWith('content://')) return video;
    final saf = await FFmpegKitConfig.getSafParameterForRead(video.path);
    if (saf == null) return null;
    return MuxInput(
      path: saf,
      kind: video.kind,
      isHlsPlaylist: video.isHlsPlaylist,
    );
  }

  /// `thumbnail` picks the most representative of the next frames, which
  /// keeps a fade to black out.
  @visibleForTesting
  static List<String> buildArgs(
    MuxInput video,
    String outputPath,
    Duration offset,
  ) => [
    '-y',
    '-hide_banner',
    '-nostats',
    '-loglevel',
    'error',
    if (offset > Duration.zero) ...['-ss', '${offset.inSeconds}'],
    ...video.ffmpegArgs,
    '-map',
    '0:v:0',
    '-vf',
    'thumbnail=30,scale=480:-2',
    '-frames:v',
    '1',
    '-q:v',
    '4',
    outputPath,
  ];
}
