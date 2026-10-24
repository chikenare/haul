import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;

  setUp(() => env = Env());

  group('DASH', () {
    test('a queued download is planned and every piece enqueued', () async {
      final engine = await env.engine();
      final (:id, :outcome) = await engine.enqueue(request());
      expect(outcome, EnqueueOutcome.created);

      await waitForStatus(engine, id, DownloadStatus.downloading);
      await waitUntil(() => env.transfer.enqueued.length == 6);

      // The video and the Latin American audio, three pieces each (init and
      // two fragments): the account's languages picked them.
      expect(
        {for (final t in env.transfer.enqueued) t.directory},
        {'haul/$id/t0', 'haul/$id/t1'},
      );
      expect(
        env.transfer.enqueued.map((t) => t.url),
        everyElement(contains('t=first')),
      );
      expect(
        env.transfer.enqueued.map((t) => t.group),
        everyElement(PluginTransferClient.pieceGroup),
      );
      expect(env.transfer.maxConcurrent, 8);
      expect(env.planFile(id).existsSync(), isTrue);

      final record = engine.byId(id)!;
      expect(record.progress.totalPieces, 6);
      expect(record.progress.donePieces, 0);
      expect(record.progress.segmented, isTrue);
    });

    test('finished pieces become a local package by default', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      expect(record.outputKind, OutputKind.package);
      final output = engine.outputPath(record)!;
      expect(output, p.join(env.work(id), 'master.m3u8'));
      expect(File(output).existsSync(), isTrue);
      expect(File(output).readAsStringSync(), contains('t0/index.m3u8'));
      expect(record.progress.donePieces, 6);
      expect(record.progress.bytes, greaterThan(0));
      expect(env.ffmpeg.runs, isEmpty);
    });

    test('as a file: merged by ffmpeg and handed to the sink', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final sink = RecordingSink(DirectorySink(() async => out.path));
      final engine = await env.engine(sink: sink);
      final (:id, outcome: _) = await engine.enqueue(
        request(
          output: OutputMode.file,
          name: const OutputName(
            baseName: 'Serie S01E01',
            folders: ['Serie', 'Season 01'],
          ),
        ),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      final expected = p.join(
        out.path,
        'Serie',
        'Season 01',
        'Serie S01E01.mkv',
      );
      expect(env.ffmpeg.runs, hasLength(1));
      expect(record.outputKind, OutputKind.file);
      expect(record.outputLocator, expected);
      expect(engine.outputPath(record), expected);
      expect(File(expected).existsSync(), isTrue);
      expect(record.stagedPath, isNull);
      expect(record.progress.bytes, File(expected).lengthSync());
      // Nothing but the record and the plan stays in the work folder.
      expect(Directory(p.join(env.work(id), 't0')).existsSync(), isFalse);
    });

    test('a taken name becomes "Name (2)"', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'))..createSync();
      File(p.join(out.path, 'La Película (2026).mkv')).writeAsStringSync('x');
      final engine = await env.engine(
        sink: DirectorySink(() async => out.path),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      expect(
        record.outputLocator,
        p.join(out.path, 'La Película (2026) (2).mkv'),
      );
    });

    test('a failed merge names it', () async {
      final engine = await env.engine(
        ffmpeg: FakeFfmpeg(error: const FfmpegException('boom\nInvalid data')),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.mux);
    });

    test('a full disk while merging names it', () async {
      final engine = await env.engine(
        ffmpeg: FakeFfmpeg(
          error: const FfmpegException('No space left on device'),
        ),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.noSpace);
    });

    test('a private file: done in the work folder, with its size', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      expect(record.outputLocator, 'work:output.mkv');
      final path = engine.outputPath(record)!;
      expect(path, p.join(env.work(id), 'output.mkv'));
      expect(record.progress.bytes, File(path).lengthSync());
      expect(record.progress.totalBytes, record.progress.bytes);
    });
  });

  test('HLS: a master with an audio rendition becomes a package', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request(url: hlsUrl));
    await waitUntil(() => env.transfer.enqueued.length == 4);

    expect(env.transfer.enqueued.map((t) => t.url).toSet(), {
      '$cdn/video/v-0.ts',
      '$cdn/video/v-1.ts',
      '$cdn/audio/a-0.ts',
      '$cdn/audio/a-1.ts',
    });
    await env.transfer.completeAll();
    final record = await waitForStatus(engine, id, DownloadStatus.done);

    final master = File(engine.outputPath(record)!).readAsStringSync();
    expect(master, contains('TYPE=AUDIO'));
    expect(master, contains('LANGUAGE="es"'));
  });

  group('plain file', () {
    test('without ranges: one task that the downloader pauses itself, '
        'passed through with its extension', () async {
      final dressed = <String>[];
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final engine = await env.engine(
        sink: DirectorySink(() async => out.path),
        hooks: EngineHooks(
          onWholeFileTask: (task, record) {
            dressed.add(record.id);
            return task.copyWith(displayName: 'dressed');
          },
        ),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(url: fileUrl, output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 1);

      final task = env.transfer.enqueued.single;
      expect(task.group, PluginTransferClient.fileGroup);
      expect(task.allowPause, isTrue);
      expect(task.headers.containsKey('Range'), isFalse);
      expect(task.updates, Updates.statusAndProgress);
      expect(task.displayName, 'dressed');
      expect(dressed, [id]);
      expect(engine.byId(id)!.progress.segmented, isFalse);

      await env.transfer.complete(task, bytes: 10);
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      expect(env.ffmpeg.runs, isEmpty);
      expect(record.outputLocator, p.join(out.path, 'La Película (2026).mp4'));
      expect(File(record.outputLocator!).lengthSync(), 10);
    });

    test('a package asked of a plain file comes out as the file', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);
      expect(record.outputKind, OutputKind.file);
      expect(record.outputLocator, 'work:output.mp4');
    });

    test('big, with ranges: one task per range with Range and If-Range, '
        'joined back', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final engine = await env.engine(
        sink: DirectorySink(() async => out.path),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(url: rangedUrl, output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 2);

      final tasks = env.transfer.enqueued;
      expect(tasks.map((t) => t.headers['Range']), [
        'bytes=0-${FileSource.rangeSize - 1}',
        'bytes=${FileSource.rangeSize}-${rangedLength - 1}',
      ]);
      expect(tasks.map((t) => t.headers['If-Range']), everyElement(etag));
      expect(tasks.map((t) => t.allowPause), everyElement(isFalse));
      expect(
        tasks.map((t) => t.group),
        everyElement(PluginTransferClient.pieceGroup),
      );
      expect(
        tasks.map((t) => t.updates),
        everyElement(Updates.statusAndProgress),
      );

      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);

      expect(env.ffmpeg.runs, isEmpty);
      final file = File(record.outputLocator!);
      expect(p.basename(file.path), 'La Película (2026).mp4');
      expect(file.lengthSync(), rangedLength);
      expect(record.progress.bytes, rangedLength);
    });

    test('no If-Range for a weak ETag', () async {
      env.routes[rangedUrl] = fileResponse(
        length: rangedLength,
        ranges: true,
        etag: 'W/"weak"',
      );
      final engine = await env.engine();
      await engine.enqueue(request(url: rangedUrl));
      await waitUntil(() => env.transfer.enqueued.length == 2);

      expect(
        env.transfer.enqueued.map((t) => t.headers.containsKey('If-Range')),
        everyElement(isFalse),
      );
    });

    test('a range of the wrong size is corrupt, and the plan goes', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: rangedUrl));
      await waitUntil(() => env.transfer.enqueued.length == 2);
      expect(env.planFile(id).existsSync(), isTrue);

      // The server ignored the range and answered something else.
      await env.transfer.complete(env.transfer.enqueued.first, bytes: 5);
      final record = await waitForStatus(engine, id, DownloadStatus.failed);

      expect(record.error?.code, DownloadErrorCode.corrupt);
      // Cleaned up right after the failure: every piece and the plan go,
      // and the other range in flight is let go.
      await waitUntil(
        () =>
            !env.planFile(id).existsSync() &&
            !Directory(p.join(env.work(id), 't0')).existsSync() &&
            env.transfer.canceledIds.isNotEmpty,
      );
      expect(env.transfer.canceledIds, [env.transfer.enqueued.last.taskId]);
    });
  });

  test("the request's headers reach every task", () async {
    const headers = {'Authorization': 'Bearer x', 'Referer': 'https://app'};
    final engine = await env.engine();
    await engine.enqueue(request(headers: headers));
    await engine.enqueue(request(key: 'big', url: rangedUrl, headers: headers));
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitUntil(() => env.transfer.enqueued.length == 8);

    for (final task in env.transfer.enqueued) {
      expect(task.headers, containsPair('Authorization', 'Bearer x'));
      expect(task.headers, containsPair('Referer', 'https://app'));
    }
    // The manifest was read with them too.
    expect(env.fetcher.requested, isNotEmpty);
  });

  test('a full disk on a piece is named', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    env.transfer.fail(
      env.transfer.enqueued.first,
      description: 'No space left on device',
    );
    final record = await waitForStatus(engine, id, DownloadStatus.failed);

    expect(record.error?.code, DownloadErrorCode.noSpace);
    expect(record.linkDead, isFalse);
  });

  test('a piece the downloader gave up on fails as network', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    env.transfer.fail(env.transfer.enqueued.first);
    final record = await waitForStatus(engine, id, DownloadStatus.failed);

    expect(record.error?.code, DownloadErrorCode.network);
    // The rest in flight is cancelled.
    // The rest in flight is cancelled, the failed one with it not.
    await waitUntil(() => env.transfer.inFlight.isEmpty);
    expect(env.transfer.canceledIds, hasLength(5));
    expect(
      env.transfer.canceledIds,
      isNot(contains(env.transfer.enqueued.first.taskId)),
    );
  });

  test('a source that cannot be read fails at once', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(
      request(url: '$cdn/missing.mpd'),
    );
    final record = await waitForStatus(engine, id, DownloadStatus.failed);

    expect(record.error, const DownloadError(code: 'http', httpStatus: 404));
    expect(env.transfer.enqueued, isEmpty);
  });

  test('titles go one at a time, oldest first', () async {
    final engine = await env.engine();
    final first = await engine.enqueue(request(key: 'a'));
    final second = await engine.enqueue(request(key: 'b', url: fileUrl));
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await settle();

    expect(engine.byId(second.id)!.status, DownloadStatus.queued);
    await env.transfer.completeAll();
    await waitForStatus(engine, first.id, DownloadStatus.done);
    await waitUntil(() => env.transfer.enqueued.length == 7);
    expect(env.transfer.enqueued.last.taskId, startsWith('ode-${second.id}-'));
  });

  test('cancelPending keeps what is finished', () async {
    final engine = await env.engine();
    final done = await engine.enqueue(request(key: 'done'));
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitForStatus(engine, done.id, DownloadStatus.done);

    final pending = await engine.enqueue(request(key: 'pending'));
    await waitForStatus(engine, pending.id, DownloadStatus.downloading);

    expect(await engine.cancelPending(), 1);
    expect(engine.byId(done.id), isNotNull);
    expect(engine.byId(pending.id), isNull);
    expect(Directory(env.work(pending.id)).existsSync(), isFalse);
  });

  test('updateMetadata replaces the app data', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request(metadata: {'a': 1}));
    await engine.updateMetadata(id, {'b': 2});
    expect(engine.byId(id)!.metadata, {'b': 2});
  });
}
