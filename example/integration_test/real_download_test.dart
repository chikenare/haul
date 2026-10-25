// A real download on the device: background_downloader, ffmpeg and the
// frame grabber for real, against a public test stream.
//
//   flutter test integration_test -d macos

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DASH to MKV, kept in the app, with a frame as its picture', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final engine = DownloadEngine(
        config: const EngineConfig(rootFolder: 'haul-it'),
        criteria: (_) async => const TrackCriteria(maxHeight: 360),
      );
      await engine.init();
      await engine.cancelPending();
      for (final r in [...engine.records]) {
        await engine.delete(r.id);
      }

      final result = await engine.enqueue(
        const DownloadRequest(
          key: 'angel-one',
          title: 'Angel One',
          name: OutputName(baseName: 'Angel One'),
          source: SourceRequest(
            url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
          ),
          output: OutputMode.file,
          parent: DownloadParent(id: 'g', title: 'Group'),
        ),
      );

      final deadline = DateTime.now().add(const Duration(minutes: 3));
      DownloadRecord? record;
      while (DateTime.now().isBefore(deadline)) {
        record = engine.byId(result.id);
        if (record?.status == DownloadStatus.failed) break;
        if (record?.status == DownloadStatus.done &&
            record?.frameLocator != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      expect(record?.error, isNull);
      expect(record?.status, DownloadStatus.done);
      final output = engine.outputPath(record!)!;
      expect(output, endsWith('.mkv'));
      expect(await File(output).length(), greaterThan(1000000));

      final image = engine.imageOf(record)!;
      expect(await File(image).length(), greaterThan(1000));
      expect(engine.parentProgress('g').isDone, isTrue);

      // ignore: avoid_print
      print('output: $output\nthumbnail: $image');
      await engine.delete(result.id);
      await engine.dispose();
      expect(await getApplicationSupportDirectory(), isNotNull);
    });
  });
}
