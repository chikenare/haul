import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:haul/src/engine/extension_points.dart';

/// The engine's own ffmpeg: ffmpeg-kit's minimal build, which stream-copies
/// every track the planner asks for into MKV. An app with another build
/// passes its own [FfmpegRunner].
class FfmpegKitRunner implements FfmpegRunner {
  const FfmpegKitRunner();

  @override
  Future<void> run(List<String> args) async {
    await quietFfmpeg();
    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    if (ReturnCode.isSuccess(code)) return;

    final log = await session.getAllLogsAsString();
    throw FfmpegException(log ?? 'ffmpeg exited with ${code?.getValue()}');
  }
}

Future<void>? _quieted;

/// ffmpeg-kit sends Dart, on the main thread, one statistics event per
/// frame and one per log line. Stream-copying runs thousands of frames a
/// second: the messages pile up faster than they are delivered and the app
/// dies out of memory. Nobody listens to them; the log that explains a
/// failure is still read off the session.
///
/// Call before every run; it only acts the first time.
Future<void> quietFfmpeg() => _quieted ??= Future.wait([
  FFmpegKitConfig.disableStatistics(),
  FFmpegKitConfig.disableLogs(),
]);
