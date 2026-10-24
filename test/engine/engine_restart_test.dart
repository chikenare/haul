import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;

  setUp(() => env = Env());

  /// Lets the JSON store's queued writes land before another engine reads.
  Future<void> flushed() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('after a kill, the next engine picks up where the disk says', () async {
    final a = await env.engine(json: true);
    final (:id, outcome: _) = await a.enqueue(request());
    final paused = await a.enqueue(request(key: 'paused'));
    await a.pause(paused.id);
    await waitUntil(() => env.transfer.enqueued.length == 6);
    final tasks = env.transfer.enqueued.toList();
    for (final task in tasks.take(2)) {
      await env.transfer.complete(task);
    }
    await flushed();
    await a.dispose();

    // While nobody listened: a third piece finished; the rest still run.
    final finishedDead = tasks[2];
    final file = env.transfer.fileOf(finishedDead);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List(10));
    env.transfer.inFlight.remove(finishedDead.taskId);
    // Leftovers: of a paused title, and of one deleted long ago.
    final ofPaused = DownloadTask(
      taskId: 'ode-${paused.id}-0-0-0',
      url: '$cdn/x',
    );
    final ofGone = DownloadTask(taskId: 'ode-gone-1-0-0', url: '$cdn/x');
    env.transfer.alive.addAll([ofPaused, ofGone]);
    final enqueuedBefore = env.transfer.enqueued.length;

    final b = await env.engine(json: true);
    await waitForStatus(b, id, DownloadStatus.downloading);
    await settle();

    expect(b.records.map((r) => r.id).toSet(), {id, paused.id});
    expect(b.byId(paused.id)!.status, DownloadStatus.paused);
    expect(
      env.transfer.canceledIds,
      containsAll([ofPaused.taskId, ofGone.taskId]),
    );
    // The three still running are followed, not asked for again.
    expect(env.transfer.enqueued.length, enqueuedBefore);
    expect(b.byId(id)!.progress.donePieces, 3);

    await env.transfer.completeAll();
    final record = await waitForStatus(b, id, DownloadStatus.done);
    expect(File(b.outputPath(record)!).existsSync(), isTrue);
    expect(env.transfer.enqueued.length, enqueuedBefore);
  });

  test('an active record is started again, not left active', () async {
    final a = await env.engine(json: true, fetcher: SilentFetcher());
    final (:id, outcome: _) = await a.enqueue(request());
    await waitForStatus(a, id, DownloadStatus.resolving);
    await flushed();
    await a.dispose();

    // Left resolving with nobody reading, it would block the queue for good.
    final b = await env.engine(json: true);
    await waitUntil(() => env.transfer.enqueued.length == 6);
    expect(b.byId(id)!.status, DownloadStatus.downloading);
  });

  test('pieces that finish while the disk is read are settled', () async {
    final a = await env.engine(json: true);
    final (:id, outcome: _) = await a.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await flushed();
    await a.dispose();

    // Every task still runs; they all finish while the next engine reads
    // the disk and before it asks the platform what it holds.
    final transfer = _FinishOnAsk(appSupport: env.dir)
      ..inFlight.addAll(env.transfer.inFlight);
    final b = DownloadEngine(
      appSupport: () async => env.dir,
      transfer: transfer,
      resolver: SourceResolver(fetcher: env.fetcher),
      logger: env.logger,
      criteria: (_) async => latinCriteria,
    );
    addTearDown(b.dispose);
    await b.init();
    await waitForStatus(b, id, DownloadStatus.done);
  });

  test('a finished download is read back done, with its output', () async {
    final a = await env.engine(json: true);
    final (:id, outcome: _) = await a.enqueue(request(output: OutputMode.file));
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitForStatus(a, id, DownloadStatus.done);
    await flushed();
    await a.dispose();

    final b = await env.engine(json: true);
    final record = b.byId(id)!;
    expect(record.status, DownloadStatus.done);
    expect(File(b.outputPath(record)!).existsSync(), isTrue);
  });

  test('a failed publish keeps the merged file: the retry only publishes '
      'again', () async {
    final out = Directory(p.join(env.dir.path, 'Movies'));
    final sink = RecordingSink(
      DirectorySink(() async => out.path),
      failures: 1,
    );
    final engine = await env.engine(sink: sink);
    final (:id, outcome: _) = await engine.enqueue(
      request(output: OutputMode.file),
    );
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    final failed = await waitForStatus(engine, id, DownloadStatus.failed);
    expect(failed.error?.code, DownloadErrorCode.publish);
    expect(failed.stagedPath, isNotNull);
    expect(env.ffmpeg.runs, hasLength(1));

    await engine.retry(id);
    final record = await waitForStatus(engine, id, DownloadStatus.done);

    expect(
      env.transfer.enqueued,
      hasLength(6),
      reason: 'nothing fetched again',
    );
    expect(env.ffmpeg.runs, hasLength(1), reason: 'nothing merged again');
    expect(File(record.outputLocator!).existsSync(), isTrue);
    expect(record.stagedPath, isNull);
  });

  test('a kill between merging and publishing only publishes again', () async {
    final held = _HeldSink();
    final a = await env.engine(json: true, sink: held);
    final (:id, outcome: _) = await a.enqueue(request(output: OutputMode.file));
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitUntil(() => held.waiting);
    await flushed();
    await a.dispose();

    final out = Directory(p.join(env.dir.path, 'Movies'));
    final b = await env.engine(
      json: true,
      sink: DirectorySink(() async => out.path),
    );
    final record = await waitForStatus(b, id, DownloadStatus.done);

    expect(env.transfer.enqueued, hasLength(6));
    expect(env.ffmpeg.runs, hasLength(1));
    expect(record.outputLocator, p.join(out.path, 'La Película (2026).mkv'));
  });

  test(
    'a disposed engine stops acting: what it was reading goes nowhere',
    () async {
      final gate = _Gate(env.fetcher);
      final store = MemoryRecordStore();
      final a = await env.engine(store: store, fetcher: gate);
      final (:id, outcome: _) = await a.enqueue(request());
      await waitForStatus(a, id, DownloadStatus.resolving);
      final saved = store.records[id];

      await a.dispose();
      gate.release();
      // The plan is written before the download would start.
      await waitUntil(() => env.planFile(id).existsSync());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(env.transfer.enqueued, isEmpty);
      expect(store.records[id], saved);
    },
  );
}

/// The second time it is asked what the platform holds — the download's
/// own ask, after reading the disk — it answers, then every piece finishes
/// before the engine follows them: their updates find nobody yet.
class _FinishOnAsk extends FakeTransferClient {
  _FinishOnAsk({required super.appSupport});

  int _asks = 0;

  @override
  Future<List<Task>> allTasks() async {
    final held = await super.allTasks();
    if (++_asks == 2) {
      for (final task in inFlight.values.toList()) {
        await complete(task);
      }
    }
    return held;
  }
}

class _HeldSink implements OutputSink {
  bool waiting = false;

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) {
    waiting = true;
    return Completer<String>().future;
  }

  @override
  Future<void> remove(String locator) async {}
}

/// Holds every fetch until [release].
class _Gate extends SourceFetcher {
  _Gate(this.inner);

  final SourceFetcher inner;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    await _gate.future;
    return inner.fetch(url, headers: headers, maxBytes: maxBytes);
  }
}
