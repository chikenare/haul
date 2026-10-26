import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';

import 'engine_test_support.dart';

/// Publishes every file at one `content://` URI, as MediaStore would.
class _UriSink implements OutputSink {
  static const uri = 'content://media/external/video/7';

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    await staged.delete();
    return uri;
  }

  @override
  Future<void> remove(String locator) async {}
}

void main() {
  late Env env;

  setUp(() => env = Env());

  Future<DownloadRecord> finished(
    DownloadEngine engine, {
    OutputMode output = OutputMode.package,
  }) async {
    final (:id, outcome: _) = await engine.enqueue(
      request(
        url: output.kind == OutputKind.file ? fileUrl : '',
        output: output,
      ),
    );
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
    return engine.byId(id)!;
  }

  test('a package: its master playlist', () async {
    final engine = await env.engine();
    final record = await finished(engine);

    final playable = await engine.playable(record);
    expect(playable?.locator, engine.outputPath(record));
  });

  test('not before it is done', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request());
    expect(await engine.playable(engine.byId(id)!), isNull);
  });

  test('a file the user deleted is nothing to open', () async {
    final engine = await env.engine();
    final record = await finished(
      engine,
      output: const OutputMode(kind: OutputKind.file),
    );
    expect(await engine.playable(record), isNotNull);

    await File(engine.outputPath(record)!).delete();
    expect(await engine.playable(record), isNull);
  });

  group('a content:// file', () {
    late FakeHaulAndroid android;
    late DownloadEngine engine;
    late DownloadRecord record;

    setUp(() async {
      android = FakeHaulAndroid();
      engine = await env.engine(sink: _UriSink(), android: android);
      record = await finished(
        engine,
        output: const OutputMode(kind: OutputKind.file),
      );
    });

    test('is opened by its URI while it is there', () async {
      expect(await engine.playable(record), isNull, reason: 'not there');
      android.existing.add(_UriSink.uri);
      expect((await engine.playable(record))?.locator, _UriSink.uri);
    });

    test('needsPath: the path behind it, or nothing', () async {
      expect(await engine.playable(record, needsPath: true), isNull);
      android.paths[_UriSink.uri] = '/storage/emulated/0/Download/a.mp4';
      expect(
        (await engine.playable(record, needsPath: true))?.locator,
        isNull,
        reason: 'that path does not exist here',
      );

      final real = File('${env.dir.path}/a.mp4')..writeAsStringSync('x');
      android.paths[_UriSink.uri] = real.path;
      expect(
        (await engine.playable(record, needsPath: true))?.locator,
        real.path,
      );
    });
  });
}
