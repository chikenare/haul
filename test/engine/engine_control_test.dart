import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

/// Remembers the most tasks it ever held at once.
class _PeakTransfer extends FakeTransferClient {
  _PeakTransfer({required super.appSupport});

  int peak = 0;

  @override
  Future<List<bool>> enqueueAll(List<DownloadTask> tasks) async {
    final results = await super.enqueueAll(tasks);
    if (inFlight.length > peak) peak = inFlight.length;
    return results;
  }
}

void main() {
  late Env env;

  setUp(() => env = Env());

  test('the window keeps at most that many pieces with the downloader, '
      'refilled as they finish', () async {
    final transfer = _PeakTransfer(appSupport: env.dir);
    final engine = DownloadEngine(
      appSupport: () async => env.dir,
      transfer: transfer,
      resolver: SourceResolver(fetcher: env.fetcher),
      store: MemoryRecordStore(),
      logger: env.logger,
      config: const EngineConfig(window: 4),
      criteria: (_) async => latinCriteria,
    );
    addTearDown(engine.dispose);
    await engine.init();
    final (:id, outcome: _) = await engine.enqueue(request());

    await waitUntil(() => transfer.enqueued.length == 4);
    await settle();
    expect(transfer.enqueued, hasLength(4));

    await transfer.complete(transfer.enqueued.first);
    await waitUntil(() => transfer.enqueued.length == 5);
    expect(transfer.inFlight, hasLength(4));

    await finish(transfer, engine, id);
    expect(transfer.enqueued, hasLength(6));
    expect(transfer.peak, 4);
    expect(
      transfer.enqueued.map((t) => t.taskId).toSet(),
      hasLength(6),
      reason: 'no piece asked twice',
    );
  });

  group('pause', () {
    test('while downloading: in flight cancelled, files and progress kept; '
        'resume asks only for what is missing', () async {
      // Every piece reported, so the test can wait for the two it finishes.
      final engine = await env.engine(
        config: const EngineConfig(progressInterval: Duration.zero),
      );
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final first = env.transfer.enqueued.take(2).toList();
      for (final task in first) {
        await env.transfer.complete(task);
      }
      await waitUntil(() => engine.byId(id)!.progress.donePieces == 2);

      await engine.pause(id);
      final paused = engine.byId(id)!;
      expect(paused.status, DownloadStatus.paused);
      expect(paused.progress.donePieces, 2);
      expect(paused.progress.totalPieces, 6);
      expect(env.transfer.inFlight, isEmpty);
      expect(env.transfer.canceledIds.toSet(), {
        for (final t in env.transfer.enqueued.skip(2)) t.taskId,
      });
      for (final task in first) {
        expect(env.transfer.fileOf(task).existsSync(), isTrue);
      }

      env.transfer.enqueued.clear();
      await engine.resume(id);
      await waitForStatus(engine, id, DownloadStatus.downloading);
      await waitUntil(() => env.transfer.enqueued.length == 4);
      await settle();

      expect(env.transfer.enqueued, hasLength(4));
      final again = {for (final t in env.transfer.enqueued) t.taskId};
      expect(again.intersection({for (final t in first) t.taskId}), isEmpty);
      expect(engine.byId(id)!.progress.donePieces, 2);

      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test('a pause of a queued title keeps it out of the queue', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(key: 'a'));
      final second = await engine.enqueue(request(key: 'b'));
      await engine.pause(second.id);

      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      await waitForStatus(engine, first.id, DownloadStatus.done);
      await settle();
      expect(engine.byId(second.id)!.status, DownloadStatus.paused);
      expect(env.transfer.enqueued, hasLength(6));
    });

    test('while the source is read wins, and nothing is written', () async {
      final fetcher = SilentFetcher();
      final engine = await env.engine(fetcher: fetcher);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitForStatus(engine, id, DownloadStatus.resolving);
      await waitUntil(() => fetcher.requested.isNotEmpty);

      await engine.pause(id);
      await settle();

      expect(engine.byId(id)!.status, DownloadStatus.paused);
      expect(env.planFile(id).existsSync(), isFalse);
      expect(env.transfer.enqueued, isEmpty);
    });

    test('a failing read after a pause is not turned into a failure', () async {
      final gate = _GatedFetcher(env.fetcher);
      final engine = await env.engine(fetcher: gate);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitForStatus(engine, id, DownloadStatus.resolving);

      await engine.pause(id);
      gate.open(error: const SourceException(SourceErrorCode.network));
      await settle();

      expect(engine.byId(id)!.status, DownloadStatus.paused);
      expect(engine.byId(id)!.error, isNull);
    });

    test('a read that answers after a pause plans nothing', () async {
      final gate = _GatedFetcher(env.fetcher);
      final engine = await env.engine(fetcher: gate);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitForStatus(engine, id, DownloadStatus.resolving);

      await engine.pause(id);
      gate.open();
      await settle();

      expect(engine.byId(id)!.status, DownloadStatus.paused);
      expect(env.planFile(id).existsSync(), isFalse);
      expect(env.transfer.enqueued, isEmpty);

      await engine.resume(id);
      await waitUntil(() => env.transfer.enqueued.length == 6);
    });
  });

  group('delete', () {
    test('while the source is read: record and folder go', () async {
      final fetcher = SilentFetcher();
      final engine = await env.engine(json: true, fetcher: fetcher);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitForStatus(engine, id, DownloadStatus.resolving);
      await waitUntil(() => Directory(env.work(id)).existsSync());

      await engine.delete(id);
      await settle();

      expect(engine.byId(id), isNull);
      expect(engine.records, isEmpty);
      expect(Directory(env.work(id)).existsSync(), isFalse);
    });

    test('while downloading: tasks cancelled, record and folder go, and the '
        'next title starts', () async {
      final engine = await env.engine(json: true);
      final first = await engine.enqueue(request(key: 'a'));
      final second = await engine.enqueue(request(key: 'b', url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.complete(env.transfer.enqueued.first);

      await engine.delete(first.id);

      expect(engine.byId(first.id), isNull);
      expect(Directory(env.work(first.id)).existsSync(), isFalse);
      expect(env.inFlightOf(first.id), isEmpty);
      await waitUntil(() => env.transfer.enqueued.length == 7);
      expect(engine.byId(second.id)!.status, DownloadStatus.downloading);

      // A piece of the deleted title that finishes late is not followed.
      await env.transfer.complete(env.transfer.enqueued[1]);
      await settle();
      expect(engine.byId(first.id), isNull);
    });

    test('of a finished file asks the sink to remove it', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final sink = RecordingSink(DirectorySink(() async => out.path));
      final engine = await env.engine(sink: sink);
      final (:id, outcome: _) = await engine.enqueue(
        request(url: fileUrl, output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 1);
      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);
      final file = File(record.outputLocator!);
      expect(file.existsSync(), isTrue);

      await engine.delete(id);

      expect(sink.removed, [record.outputLocator]);
      expect(file.existsSync(), isFalse);
      expect(Directory(env.work(id)).existsSync(), isFalse);
    });

    test('of a finished package removes its folder only', () async {
      final sink = RecordingSink(const PrivateSink());
      final engine = await env.engine(sink: sink);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);

      await engine.delete(id);
      expect(sink.removed, isEmpty);
      expect(Directory(env.work(id)).existsSync(), isFalse);
    });
  });

  group('canceled updates', () {
    test(
      'a pending piece cancelled by someone else is asked for again',
      () async {
        final engine = await env.engine();
        final (:id, outcome: _) = await engine.enqueue(request());
        await waitUntil(() => env.transfer.enqueued.length == 6);
        final victim = env.transfer.enqueued.first;

        // A notification button, or the system.
        env.transfer.inFlight.remove(victim.taskId);
        env.transfer.emit(TaskStatusUpdate(victim, TaskStatus.canceled));
        await waitUntil(() => env.transfer.enqueued.length == 7);

        expect(env.transfer.enqueued.last.taskId, victim.taskId);
        expect(engine.byId(id)!.status, DownloadStatus.downloading);

        await env.transfer.completeAll();
        await waitForStatus(engine, id, DownloadStatus.done);
      },
    );

    test('the engine\'s own cancels, reported after a quick resume, are not '
        'asked for twice', () async {
      env.transfer.holdCancels = true;
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);

      await engine.pause(id);
      await engine.resume(id);
      await waitUntil(() => env.transfer.enqueued.length == 12);

      // The plugin reports the pause's cancels only now.
      expect(env.transfer.heldCancels, hasLength(6));
      env.transfer.releaseCancels();
      await settle();

      expect(env.transfer.enqueued, hasLength(12));
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test('a foreign cancel of a piece still waiting for room is not enqueued '
        'beside the feeder', () async {
      final engine = await env.engine(config: const EngineConfig(window: 2));
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 2);
      // A late report from an earlier run, for a piece not handed over yet.
      final waiting = env.transfer.enqueued.first.copyWith(
        taskId: 'ode-$id-1-1-2',
      );
      env.transfer.emit(TaskStatusUpdate(waiting, TaskStatus.canceled));
      await settle();

      expect(env.transfer.enqueued, hasLength(2));
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
      expect(env.transfer.enqueued.map((t) => t.taskId).toSet(), hasLength(6));
      expect(env.transfer.enqueued, hasLength(6));
    });

    test('after a retry, updates of the failed run count for nothing, and '
        'a real cancel of the new run is still asked for again', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final old = env.transfer.enqueued.toList();
      env.transfer.fail(old.first);
      await waitForStatus(engine, id, DownloadStatus.failed);
      await waitUntil(() => env.transfer.inFlight.isEmpty);

      env.transfer.enqueued.clear();
      await engine.retry(id);
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final fresh = env.transfer.enqueued.toList();
      expect(
        fresh.map((t) => t.taskId).toSet().intersection({
          for (final t in old) t.taskId,
        }),
        isEmpty,
        reason: 'a new run, new task ids',
      );

      // Late reports of the first run: none is a piece of this one.
      env.transfer.emit(TaskStatusUpdate(old[1], TaskStatus.canceled));
      env.transfer.emit(TaskStatusUpdate(old[2], TaskStatus.complete));
      env.transfer.emit(TaskStatusUpdate(old[3], TaskStatus.failed));
      await settle();
      expect(engine.byId(id)!.status, DownloadStatus.downloading);
      expect(env.transfer.enqueued, hasLength(6));

      final victim = fresh.first;
      env.transfer.inFlight.remove(victim.taskId);
      env.transfer.emit(TaskStatusUpdate(victim, TaskStatus.canceled));
      await waitUntil(() => env.transfer.enqueued.length == 7);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });
  });

  test(
    'a piece running for a download that is not moving is cancelled',
    () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await engine.pause(id);
      final stray = env.transfer.enqueued.first;
      env.transfer.canceledIds.clear();

      env.transfer.emit(TaskStatusUpdate(stray, TaskStatus.running));
      await settle();
      expect(env.transfer.canceledIds, [stray.taskId]);
    },
  );

  test('a refused enqueue fails the download instead of waiting', () async {
    final engine = await env.engine();
    env.transfer.refuseNext = true;
    final (:id, outcome: _) = await engine.enqueue(request());
    final record = await waitForStatus(engine, id, DownloadStatus.failed);
    expect(record.error?.code, DownloadErrorCode.unknown);
  });
}

/// Holds the first fetch until [open]; the rest go straight to [inner].
class _GatedFetcher extends SourceFetcher {
  _GatedFetcher(this.inner);

  final SourceFetcher inner;
  final _gate = Completer<Object?>();
  var _first = true;

  void open({Object? error}) => _gate.complete(error);

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    if (_first) {
      _first = false;
      if (await _gate.future case final error?) throw error;
    }
    return inner.fetch(url, headers: headers, maxBytes: maxBytes);
  }
}
