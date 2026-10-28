import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

import 'engine_test_support.dart';

/// An HLS's weight comes from its bitrate, often the peak: once enough
/// pieces are in, the total is projected from what they weigh.
void main() {
  late Env env;

  String media(String prefix, int count) => [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:4',
    for (var i = 0; i < count; i++) ...['#EXTINF:4.0,', '$prefix-$i.ts'],
    '#EXT-X-ENDLIST',
    '',
  ].join('\n');

  setUp(() {
    env = Env();
    env.routes['$cdn/video/720.m3u8'] = (url) => FetchedResponse(
      url: url,
      headers: const {},
      body: media('v', 10).codeUnits,
    );
    env.routes['$cdn/audio/es.m3u8'] = (url) => FetchedResponse(
      url: url,
      headers: const {},
      body: media('a', 10).codeUnits,
    );
  });

  int trackOf(DownloadTask task) => int.parse(task.taskId.split('-')[3]);

  Future<void> completeTrack(int t, int count, int bytes) async {
    for (var i = 0; i < count; i++) {
      await waitUntil(
        () => env.transfer.inFlight.values.any((k) => trackOf(k) == t),
      );
      final task = env.transfer.inFlight.values.firstWhere(
        (k) => trackOf(k) == t,
      );
      await env.transfer.complete(task, bytes: bytes);
    }
  }

  test('the total follows the pieces, track by track', () async {
    final engine = await env.engine(
      config: const EngineConfig(progressInterval: Duration.zero),
    );
    final (:id, outcome: _) = await engine.enqueue(request(url: hlsUrl));
    await waitForStatus(engine, id, DownloadStatus.downloading);

    // 40 s: the variant's 1 Mb/s less a guessed 128 kb/s audio, and that
    // audio.
    const audioGuess = 128000 * 40 ~/ 8;
    expect(engine.byId(id)!.progress.totalBytes, 1000000 * 40 ~/ 8);

    await completeTrack(0, 5, 1000);
    await waitUntil(
      () => engine.byId(id)!.progress.totalBytes == 10 * 1000 + audioGuess,
    );

    await completeTrack(0, 5, 1000);
    await completeTrack(1, 5, 100);
    await waitUntil(
      () => engine.byId(id)!.progress.totalBytes == 10 * 1000 + 10 * 100,
    );
    expect(engine.byId(id)!.status, DownloadStatus.downloading);
  });
}
