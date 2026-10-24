// Regressions of the engine review: races between runs, recovery after a
// kill at every checkpoint, pieces that are not what was planned, and the
// platform pausing tasks. Numbers refer to the review's findings.

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;

  setUp(() => env = Env());

  Future<void> flushed() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  int runOf(String taskId) => int.parse(taskId.split('-')[2]);

  group('#1 runs', () {
    test('a quick pause and resume: the tasks still being cancelled are '
        'not taken for the new run, and nothing stalls', () async {
      env.transfer.holdCancels = true;
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final first = env.transfer.enqueued.toList();

      await engine.pause(id);
      // Still listed by the platform: their cancel is not reported yet.
      expect(env.transfer.cancelling, hasLength(6));
      await engine.resume(id);
      await waitUntil(() => env.transfer.enqueued.length == 12);

      final second = env.transfer.enqueued.skip(6).toList();
      expect(second.map((t) => runOf(t.taskId)), everyElement(2));
      expect(first.map((t) => runOf(t.taskId)), everyElement(1));

      env.transfer.releaseCancels();
      await settle();
      expect(env.transfer.enqueued, hasLength(12));
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test('delete and enqueue again under the same key, with the cancels '
        'not reported yet, downloads as new', () async {
      env.transfer.holdCancels = true;
      final engine = await env.engine();
      final first = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await engine.delete(first.id);

      final second = await engine.enqueue(request());
      expect(second.outcome, EnqueueOutcome.created);
      await waitUntil(() => env.transfer.enqueued.length == 12);
      env.transfer.releaseCancels();
      await env.transfer.completeAll();
      await waitForStatus(engine, second.id, DownloadStatus.done);
    });

    test('after a kill only the tasks of the last run are followed; an '
        'older run still being cancelled is let go', () async {
      final store = MemoryRecordStore();
      final a = await env.engine(store: store);
      final (:id, outcome: _) = await a.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await a.dispose();

      // Left by a pause of an earlier run that the kill cut short.
      final older = env.transfer.enqueued.first.copyWith(
        taskId: 'ode-$id-0-0-0',
      );
      env.transfer.alive.add(older);
      final before = env.transfer.enqueued.length;

      final b = await env.engine(store: store);
      await waitForStatus(b, id, DownloadStatus.downloading);
      await settle();

      expect(env.transfer.canceledIds, contains(older.taskId));
      expect(env.transfer.enqueued.length, before, reason: 'run 1 followed');
      await env.transfer.completeAll();
      await waitForStatus(b, id, DownloadStatus.done);
    });

    test('a refresh after a kill cancels what the last run left, and asks '
        'again under a new run', () async {
      final store = MemoryRecordStore();
      final a = await env.engine(store: store);
      final (:id, outcome: _) = await a.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await a.dispose();
      store.records[id] = store.records[id]!.copyWith(linkDead: true);

      final b = await env.engine(
        store: store,
        refresher: FakeRefresher(SourceRequest(url: dashUrl('fresh'))),
      );
      await waitUntil(() => env.transfer.enqueued.length == 12);
      expect(
        env.transfer.enqueued.skip(6).map((t) => runOf(t.taskId)),
        everyElement(2),
      );
      expect(env.transfer.canceledIds, hasLength(6));
      await env.transfer.completeAll();
      await waitForStatus(b, id, DownloadStatus.done);
    });
  });

  group('#2 a failed one asked again', () {
    test('with other tracks after it was planned: planned again', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      env.transfer.fail(env.transfer.enqueued.last, httpStatus: 500);
      await waitForStatus(engine, id, DownloadStatus.failed);

      final again = await engine.enqueue(
        request(tracks: const TrackChoice.criteria(englishCriteria)),
      );
      expect(again.outcome, EnqueueOutcome.replacedFailed);
      await waitForStatus(engine, id, DownloadStatus.downloading);
      expect(
        env
            .plan(id)
            .tracks
            .where((t) => t.kind == TrackKind.audio)
            .single
            .language,
        'en',
      );
      expect(engine.byId(id)!.replan, isFalse);
    });

    test('with a new source: read again without asking the refresher, and '
        'the pieces that line up kept', () async {
      final refresher = FakeRefresher(SourceRequest(url: dashUrl('minted')));
      final engine = await env.engine(refresher: refresher);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final kept = env.transfer.enqueued.first;
      await env.transfer.complete(kept);
      env.transfer.fail(env.transfer.enqueued.last, httpStatus: 403);
      await waitForStatus(engine, id, DownloadStatus.failed);

      env.transfer.enqueued.clear();
      await engine.enqueue(request(url: dashUrl('second')));
      await waitUntil(() => env.transfer.enqueued.length == 5);

      expect(refresher.calls, isEmpty);
      expect(
        env.transfer.enqueued.map((t) => t.url),
        everyElement(contains('t=second')),
      );
      expect(env.transfer.fileOf(kept).existsSync(), isTrue);
      expect(engine.byId(id)!.linkDead, isFalse);
    });

    test('as a package after a failed publish: the old file is not '
        'published, the pieces come again', () async {
      final engine = await env.engine(
        sink: RecordingSink(const PrivateSink(), failures: 1),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.failed);
      expect(File(p.join(env.work(id), 'output.mkv')).existsSync(), isTrue);

      await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 12);
      expect(File(p.join(env.work(id), 'output.mkv')).existsSync(), isFalse);
      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);
      expect(record.outputKind, OutputKind.package);
    });
  });

  group('#3 #8 pieces that are not the file planned', () {
    test('a corrupt range wipes every piece; the retry plans again with the '
        'new ETag and asks for all of them', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: rangedUrl));
      await waitUntil(() => env.transfer.enqueued.length == 2);
      final [good, bad] = env.transfer.enqueued.toList();
      await env.transfer.complete(good);
      await env.transfer.complete(bad, bytes: 5);
      await waitForStatus(engine, id, DownloadStatus.failed);
      await waitUntil(
        () =>
            !Directory(p.join(env.work(id), 't0')).existsSync() &&
            !env.planFile(id).existsSync(),
      );

      env.routes[rangedUrl] = fileResponse(
        length: rangedLength,
        ranges: true,
        etag: '"v2"',
      );
      env.transfer.enqueued.clear();
      await engine.retry(id);
      await waitUntil(() => env.transfer.enqueued.length == 2);
      expect(
        env.transfer.enqueued.map((t) => t.headers['If-Range']),
        everyElement('"v2"'),
      );
      await env.transfer.completeAll();
      final record = await waitForStatus(engine, id, DownloadStatus.done);
      expect(File(engine.outputPath(record)!).lengthSync(), rangedLength);
    });

    test('a range answered whole (If-Range no longer matched) fails on its '
        'first progress, not after fetching the whole file', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: rangedUrl));
      await waitUntil(() => env.transfer.enqueued.length == 2);

      env.transfer.emitProgress(
        TaskProgressUpdate(env.transfer.enqueued.first, 0.01, rangedLength),
      );
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.corrupt);
      await waitUntil(() => env.transfer.inFlight.isEmpty);
      await waitUntil(() => !env.planFile(id).existsSync());
    });

    test('a 416 is not the file planned either', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: rangedUrl));
      await waitUntil(() => env.transfer.enqueued.length == 2);
      await env.transfer.complete(env.transfer.enqueued.first);

      env.transfer.fail(env.transfer.enqueued.last, httpStatus: 416);
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.corrupt);
      expect(record.linkDead, isFalse);
      // The wipe removes the folder's entries in any order.
      await waitUntil(
        () =>
            !env.planFile(id).existsSync() &&
            !Directory(p.join(env.work(id), 't0')).existsSync(),
      );
    });
  });

  group('#4 tasks the platform paused', () {
    test('are resumed', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      final task = env.transfer.enqueued.single;

      env.transfer.pauseByPlatform(task);
      await waitUntil(() => env.transfer.resumed.isNotEmpty);
      expect(env.transfer.inFlight.keys, [task.taskId]);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test('that cannot resume are cancelled and asked for again', () async {
      env.transfer.refuseResume = true;
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);

      env.transfer.pauseByPlatform(env.transfer.enqueued.single);
      await waitUntil(() => env.transfer.enqueued.length == 2);
      expect(env.transfer.paused, isEmpty);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test('before a kill are resumed when followed again', () async {
      final store = MemoryRecordStore();
      final a = await env.engine(store: store);
      final (:id, outcome: _) = await a.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      final task = env.transfer.enqueued.single;
      await a.dispose();
      // Paused while nobody listened: listed, and waiting.
      env.transfer.inFlight.remove(task.taskId);
      env.transfer.paused[task.taskId] = task;

      final b = await env.engine(store: store);
      await waitUntil(() => env.transfer.resumed.contains(task.taskId));
      expect(env.transfer.enqueued, hasLength(1));
      await env.transfer.completeAll();
      await waitForStatus(b, id, DownloadStatus.done);
    });
  });

  group('#5 #6 #10 kills while the one file is published', () {
    test('after the sink moved the file, before the record said done: the '
        'file is found, nothing fetched or published twice', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final store = MemoryRecordStore();
      final a = await env.engine(
        store: store,
        sink: _KilledAfterMove(DirectorySink(() async => out.path)),
      );
      final (:id, outcome: _) = await a.enqueue(
        request(output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      final target = p.join(out.path, 'La Película (2026).mkv');
      await waitUntil(() => File(target).existsSync());
      await a.dispose();
      expect(store.records[id]!.status, DownloadStatus.assembling);

      final b = await env.engine(
        store: store,
        sink: DirectorySink(() async => out.path),
      );
      final record = await waitForStatus(b, id, DownloadStatus.done);

      expect(record.outputLocator, target);
      expect(env.transfer.enqueued, hasLength(6));
      expect(env.ffmpeg.runs, hasLength(1));
      expect(out.listSync(), hasLength(1));
    });

    test('a passed-through file renamed before the record knew: published '
        'without fetching again', () async {
      final store = MemoryRecordStore();
      final held = _HeldSink();
      final a = await env.engine(store: store, sink: held);
      final (:id, outcome: _) = await a.enqueue(
        request(url: fileUrl, output: OutputMode.file),
      );
      await waitUntil(() => env.transfer.enqueued.length == 1);
      await env.transfer.completeAll();
      await waitUntil(() => held.waiting);
      await a.dispose();
      // As if the kill fell between the rename and saving the record.
      store.records[id] = store.records[id]!.copyWith(stagedPath: null);

      final b = await env.engine(store: store);
      final record = await waitForStatus(b, id, DownloadStatus.done);
      expect(record.outputLocator, 'work:output.mp4');
      expect(env.transfer.enqueued, hasLength(1));
    });

    test('a kill before the pieces were tidied: tidied on the next run, '
        'sidecars listed', () async {
      final store = MemoryRecordStore();
      final held = _HeldSink();
      final a = await env.engine(store: store, sink: held);
      final (:id, outcome: _) = await a.enqueue(
        request(
          tracks: const TrackChoice.criteria(
            TrackCriteria(audio: LanguageTracks(['es-419'])),
          ),
          subtitles: {'Español': subtitleUrl},
          output: const OutputMode(
            kind: OutputKind.file,
            subtitleSidecars: true,
          ),
        ),
      );
      await waitUntil(() => env.transfer.enqueued.length == 7);
      await env.transfer.completeAll();
      await waitUntil(() => held.waiting);
      await a.dispose();
      // Undo the tidying, as a kill right after the merge would leave it.
      final work = env.work(id);
      Directory(p.join(work, 'subs')).deleteSync(recursive: true);
      File(p.join(work, 'subtitles.json')).deleteSync();
      File(p.join(work, 't2', '0.vtt')).createSync(recursive: true);
      File(p.join(work, 't0', '0.mp4')).createSync(recursive: true);

      final b = await env.engine(store: store);
      await waitForStatus(b, id, DownloadStatus.done);
      expect(Directory(p.join(work, 't0')).existsSync(), isFalse);
      expect(Directory(p.join(work, 't2')).existsSync(), isFalse);
      expect((await b.subtitlesOf(id)).single.label, 'Español');
      expect(env.ffmpeg.runs, hasLength(1));
    });

    test('a source that cannot be deleted after its copy does not fail the '
        'publish', () async {
      final from = Directory(p.join(env.dir.path, 'locked'))..createSync();
      final file = File(p.join(from.path, 'output.mkv'))
        ..writeAsStringSync('movie');
      final to = p.join(env.dir.path, 'out.mkv');
      // Its folder read-only: the file cannot be deleted.
      await Process.run('chmod', ['555', from.path]);
      addTearDown(() => Process.run('chmod', ['755', from.path]));

      await moveFile(
        file,
        to,
        rename: (_, _) =>
            Future.error(const FileSystemException('Cross-device link')),
      );
      expect(File(to).readAsStringSync(), 'movie');
    }, skip: Platform.isWindows);
  });

  group('#7 a whole file cut short', () {
    test('is asked for again when found at start', () async {
      final store = MemoryRecordStore();
      final a = await env.engine(store: store);
      final (:id, outcome: _) = await a.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      final task = env.transfer.enqueued.single;
      await a.dispose();
      // A copy cut short by the kill.
      env.transfer.inFlight.clear();
      final file = env.transfer.fileOf(task)..createSync(recursive: true);
      file.writeAsBytesSync(Uint8List(4));

      final b = await env.engine(store: store);
      await waitUntil(() => env.transfer.enqueued.length == 2);
      await env.transfer.completeAll();
      final record = await waitForStatus(b, id, DownloadStatus.done);
      expect(File(b.outputPath(record)!).lengthSync(), 10);
    });

    test('is corrupt when reported complete', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      await env.transfer.complete(env.transfer.enqueued.single, bytes: 4);
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.corrupt);
    });

    test('on desktop a fragment on disk counts only once reported complete, '
        'even when the report came before the job', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = MemoryRecordStore();
      final a = await env.engine(store: store);
      final (:id, outcome: _) = await a.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await a.dispose();

      final tasks = env.transfer.enqueued.toList();
      final transfer = _AskHook(appSupport: env.dir)
        ..inFlight.addAll(env.transfer.inFlight);
      // While the next engine reads the disk: one piece is still being
      // copied into place, another finishes and is reported to nobody.
      transfer.onSecondAsk = () async {
        env.transfer.fileOf(tasks[0])
          ..createSync(recursive: true)
          ..writeAsBytesSync(Uint8List(3));
        await transfer.complete(tasks[1]);
      };
      final b = DownloadEngine(
        appSupport: () async => env.dir,
        transfer: transfer,
        resolver: SourceResolver(fetcher: env.fetcher),
        store: store,
        logger: env.logger,
        criteria: (_) async => latinCriteria,
        config: const EngineConfig(progressInterval: Duration.zero),
      );
      addTearDown(b.dispose);
      await b.init();
      await waitUntil(() => b.byId(id)!.progress.donePieces == 1);
      await settle();
      expect(b.byId(id)!.progress.donePieces, 1, reason: 'the copy waits');

      await transfer.completeAll();
      await waitForStatus(b, id, DownloadStatus.done);
    });
  });

  test(
    '#9 a refused enqueue leaves nothing behind: the retry downloads',
    () async {
      final engine = await env.engine(config: const EngineConfig(window: 6));
      env.transfer.refuseNext = true;
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitForStatus(engine, id, DownloadStatus.failed);
      expect(env.transfer.allTasks(), completion(isEmpty));

      await engine.retry(id);
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    },
  );

  test('#11 a delete with a folder that cannot go is not read back', () async {
    final root = Directory(p.join(env.dir.path, 'records'))..createSync();
    final store = JsonRecordStore(() async => root);
    final now = DateTime(2026);
    await store.save(
      DownloadRecord(
        id: 'r1',
        key: 'k',
        title: 't',
        name: const OutputName(baseName: 't'),
        status: DownloadStatus.done,
        source: const SourceRequest(url: fileUrl),
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Neither renamed into the trash nor removed: the root is read-only.
    await Process.run('chmod', ['555', root.path]);
    addTearDown(() => Process.run('chmod', ['755', root.path]));

    await store.delete('r1');
    expect(File(p.join(root.path, 'r1', 'record.json')).existsSync(), isFalse);
    await Process.run('chmod', ['755', root.path]);
    expect(await JsonRecordStore(() async => root).loadAll(), isEmpty);
  }, skip: Platform.isWindows);

  test('#13 a failed init is tried again', () async {
    var calls = 0;
    final engine = DownloadEngine(
      appSupport: () async {
        if (calls++ == 0) throw const FileSystemException('not yet');
        return env.dir;
      },
      transfer: env.transfer,
      resolver: SourceResolver(fetcher: env.fetcher),
      store: MemoryRecordStore(),
      logger: env.logger,
      criteria: (_) async => latinCriteria,
    );
    addTearDown(engine.dispose);

    await expectLater(engine.init(), throwsA(isA<FileSystemException>()));
    await engine.init();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitForStatus(engine, id, DownloadStatus.downloading);
  });

  test('#14 a piece reported twice counts once', () async {
    final engine = await env.engine(
      config: const EngineConfig(progressInterval: Duration.zero),
    );
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    final task = env.transfer.enqueued.first;

    await env.transfer.complete(task);
    env.transfer.emit(TaskStatusUpdate(task, TaskStatus.complete));
    await waitUntil(() => engine.byId(id)!.progress.donePieces == 1);
    await settle();
    expect(engine.byId(id)!.progress.donePieces, 1);
  });

  test(
    '#15 a pause while the refresher answers keeps the fresh link',
    () async {
      final refresher = _GatedRefresher(
        SourceRequest(url: dashUrl('fresh')),
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final engine = await env.engine(refresher: refresher);
      final (:id, outcome: _) = await engine.enqueue(
        request(expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      await waitUntil(() => refresher.calls == 1);

      await engine.pause(id);
      refresher.release();
      await settle();
      expect(engine.byId(id)!.source.url, dashUrl('fresh'));
      expect(engine.byId(id)!.status, DownloadStatus.paused);

      await engine.resume(id);
      await waitUntil(() => env.transfer.enqueued.length == 6);
      expect(refresher.calls, 1, reason: 'not minted twice');
    },
  );

  test('#16 after a kill, the download that was running goes first', () async {
    final store = MemoryRecordStore();
    final a = await env.engine(store: store);
    final older = await a.enqueue(request(key: 'older'));
    await a.pause(older.id);
    final running = await a.enqueue(request(key: 'running'));
    await waitForStatus(a, running.id, DownloadStatus.downloading);
    await a.resume(older.id);
    await flushed();
    await a.dispose();

    final b = await env.engine(store: store);
    await waitForStatus(b, running.id, DownloadStatus.downloading);
    expect(b.byId(older.id)!.status, DownloadStatus.queued);
  });
}

/// Moves the file and is killed before it can answer.
class _KilledAfterMove implements ReservingOutputSink {
  _KilledAfterMove(this.inner);

  final ReservingOutputSink inner;

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) => inner.publish(staged, name, extension, record);

  @override
  Future<String?> reserve(
    OutputName name,
    String extension,
    DownloadRecord record,
  ) => inner.reserve(name, extension, record);

  @override
  Future<String> publishTo(
    File staged,
    String locator,
    DownloadRecord record,
  ) async {
    await inner.publishTo(staged, locator, record);
    return Completer<String>().future;
  }

  @override
  Future<bool> holds(String locator) => inner.holds(locator);

  @override
  Future<void> remove(String locator) => inner.remove(locator);
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

/// Runs [onSecondAsk] the second time it is asked what the platform holds
/// — the download's own ask, after it read the disk — after answering.
class _AskHook extends FakeTransferClient {
  _AskHook({required super.appSupport});

  Future<void> Function()? onSecondAsk;
  int _asks = 0;

  @override
  Future<List<Task>> allTasks() async {
    final held = await super.allTasks();
    if (++_asks == 2) await onSecondAsk?.call();
    return held;
  }
}

class _GatedRefresher implements SourceRefresher {
  _GatedRefresher(this.source, {this.expiresAt});

  final SourceRequest source;
  final DateTime? expiresAt;
  final _gate = Completer<void>();
  int calls = 0;

  void release() => _gate.complete();

  @override
  Future<RefreshedSource> refresh(DownloadRecord record) async {
    calls++;
    if (calls == 1) await _gate.future;
    return RefreshedSource(source, expiresAt: expiresAt);
  }
}
