import 'package:media_planner/src/assembly/mux_input.dart';
import 'package:media_planner/src/language_codes.dart';
import 'package:media_planner/src/plan.dart';
import 'package:path/path.dart' as p;

/// The ffmpeg arguments that merge a download's tracks into one MKV without
/// re-encoding. Running ffmpeg is the app's: this only builds the list.
///
/// MKV because it takes any codec that arrives (H.264/H.265/AV1/VP9,
/// AAC/Opus/AC-3) and several audios and subtitles. The only conversion is
/// external subtitles to SRT, which any player understands.
abstract final class MkvArgs {
  /// Never a single string: titles carry quotes and spaces.
  ///
  /// The order of the `-map`s decides the output indexes, and with them which
  /// stream each piece of metadata lands on: the video first, then the
  /// separate audios (their indexes are known), then the audio the video
  /// itself carries, and the same for subtitles. What already came inside the
  /// video is copied as it is, with its language.
  static List<String> build({
    required List<MuxInput> inputs,
    required String outputPath,
    String? title,
  }) {
    final args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-loglevel',
      'error',
    ];

    for (final input in inputs) {
      args.addAll(input.ffmpegArgs);
    }

    List<int> indexesOf(TrackKind kind) => [
      for (final (i, input) in inputs.indexed)
        if (input.kind == kind) i,
    ];
    final videos = indexesOf(TrackKind.video);
    final audios = indexesOf(TrackKind.audio);
    final subtitles = indexesOf(TrackKind.subtitle);

    // With `?`: an audio-only HLS (a radio, a podcast) merges too.
    for (final i in videos) {
      args.addAll(['-map', '$i:v?']);
    }
    for (final i in audios) {
      args.addAll(['-map', '$i:a:0']);
    }
    for (final i in videos) {
      args.addAll(['-map', '$i:a?']);
    }
    for (final i in subtitles) {
      args.addAll(['-map', '$i:s:0']);
    }
    for (final i in videos) {
      // `t`: the fonts attached to an MKV with ASS subtitles.
      args.addAll(['-map', '$i:s?', '-map', '$i:t?']);
    }

    args.addAll(['-c', 'copy']);
    // An MP4's subtitles are `mov_text`, which Matroska does not take: all go
    // to SRT. Elsewhere (MKV, TS…) the video's own are copied as they are —
    // they may be images (PGS) and do not convert.
    final mp4Subtitles = videos.any(
      (i) => _mp4Extensions.contains(p.extension(inputs[i].path).toLowerCase()),
    );
    if (mp4Subtitles) args.addAll(['-c:s', 'srt']);

    for (final (k, i) in audios.indexed) {
      args.addAll(_metadata('a', k, inputs[i]));
    }
    // An HLS video arrives with no default mark.
    if (videos.isNotEmpty) args.addAll(['-disposition:v:0', 'default']);
    // An MP4 marks its audio as default: unless cleared, every separate
    // track would be.
    for (var k = 0; k < audios.length; k++) {
      args.addAll(['-disposition:a:$k', k == 0 ? 'default' : '0']);
    }

    for (final (k, i) in subtitles.indexed) {
      if (!mp4Subtitles) args.addAll(['-c:s:$k', 'srt']);
      args.addAll(_metadata('s', k, inputs[i]));
      if (inputs[i].forced) args.addAll(['-disposition:s:$k', 'forced']);
    }

    if (title != null && title.isNotEmpty) {
      args.addAll(['-metadata', 'title=$title']);
    }

    args.add(outputPath);
    return args;
  }

  static const _mp4Extensions = {'.mp4', '.m4v', '.mov', '.3gp'};

  static List<String> _metadata(String kind, int index, MuxInput input) => [
    if (input.language case final language?) ...[
      '-metadata:s:$kind:$index',
      'language=${iso6392(language)}',
    ],
    if (input.label case final label? when label.isNotEmpty) ...[
      '-metadata:s:$kind:$index',
      'title=$label',
    ],
  ];
}
