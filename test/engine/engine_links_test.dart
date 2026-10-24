import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;

  setUp(() => env = Env());

  /// Two pieces on disk, then the server refuses a third with [status].
  Future<String> refusedAfterTwo(
    DownloadEngine engine, {
    int status = 403,
  }) async {
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    for (final task in env.transfer.enqueued.take(2).toList()) {
      await env.transfer.complete(task);
    }
    env.transfer.fail(env.transfer.enqueued.last, httpStatus: status);
    await waitForStatus(engine, id, DownloadStatus.failed);
    return id;
  }

  test(
    'a refused piece fails with its status and marks the link dead',
    () async {
      final engine = await env.engine();
      final id = await refusedAfterTwo(engine);

      final record = engine.byId(id)!;
      expect(
        record.error,
        const DownloadError(code: DownloadErrorCode.http, httpStatus: 403),
      );
      expect(record.linkDead, isTrue);
      await waitUntil(() => env.transfer.inFlight.isEmpty);
    },
  );

  test('a 500 is not a dead link', () async {
    final engine = await env.engine();
    final id = await refusedAfterTwo(engine, status: 500);
    expect(engine.byId(id)!.linkDead, isFalse);
    expect(engine.byId(id)!.error?.httpStatus, 500);
  });

  test('the retry of a dead link asks the refresher, and keeps the pieces '
      'when the fresh plan lines up', () async {
    final refresher = FakeRefresher(
      SourceRequest(url: dashUrl('fresh')),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      metadata: {'minted': true},
    );
    final engine = await env.engine(refresher: refresher);
    final id = await refusedAfterTwo(engine);
    final kept = env.transfer.enqueued.take(2).toList();
    expect(refresher.calls, isEmpty);

    env.transfer.enqueued.clear();
    await engine.retry(id);
    await waitForStatus(engine, id, DownloadStatus.downloading);
    await waitUntil(() => env.transfer.enqueued.length == 4);
    await settle();

    expect(refresher.calls, hasLength(1));
    expect(refresher.calls.single.id, id);
    expect(env.transfer.enqueued, hasLength(4));
    expect(
      env.transfer.enqueued.map((t) => t.url),
      everyElement(contains('t=fresh')),
    );
    for (final task in kept) {
      expect(env.transfer.fileOf(task).existsSync(), isTrue);
    }
    expect(env.plan(id).tracks.first.pieces.first.url, contains('t=fresh'));

    final record = engine.byId(id)!;
    expect(record.source.url, dashUrl('fresh'));
    expect(record.linkDead, isFalse);
    expect(record.metadata, {'minted': true});
    expect(record.error, isNull);
    expect(record.progress.donePieces, 2);

    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
  });

  test('a fresh plan that does not line up starts over', () async {
    final refresher = FakeRefresher(SourceRequest(url: longDashUrl()));
    final engine = await env.engine(refresher: refresher);
    final id = await refusedAfterTwo(engine);
    final old = env.transfer.enqueued.take(2).toList();

    env.transfer.enqueued.clear();
    await engine.retry(id);
    // Three fragments and the init, per track.
    await waitUntil(() => env.transfer.enqueued.length == 8);

    for (final task in old) {
      expect(env.transfer.fileOf(task).existsSync(), isFalse);
    }
    expect(engine.byId(id)!.progress.donePieces, 0);
    expect(engine.byId(id)!.progress.totalPieces, 8);
  });

  test('the fresh plan keeps the choice it was made with, whatever the '
      'preferences say by now', () async {
    var criteria = latinCriteria;
    final engine = await env.engine(
      refresher: FakeRefresher(SourceRequest(url: dashUrl('fresh'))),
      criteria: (_) async => criteria,
    );
    final id = await refusedAfterTwo(engine);

    criteria = englishCriteria;
    await engine.retry(id);
    await waitForStatus(engine, id, DownloadStatus.downloading);

    expect(env.plan(id).tracks[1].language, 'es-419');
  });

  test(
    'a refusal from the refresher fails with its code and message',
    () async {
      final engine = await env.engine(
        refresher: FakeRefresher(
          SourceRequest(url: dashUrl('fresh')),
          error: const RefreshException('quota_exhausted', 'Allowance spent'),
        ),
      );
      final id = await refusedAfterTwo(engine);

      await engine.retry(id);
      await waitUntil(() => engine.byId(id)!.error != null);
      final record = engine.byId(id)!;
      expect(record.status, DownloadStatus.failed);
      expect(
        record.error,
        const DownloadError(
          code: 'quota_exhausted',
          message: 'Allowance spent',
        ),
      );
      // Still dead: the next retry asks again.
      expect(record.linkDead, isTrue);
    },
  );

  test(
    'anything else from the refresher is reported, and fails unknown',
    () async {
      final engine = await env.engine(
        refresher: FakeRefresher(
          SourceRequest(url: dashUrl('fresh')),
          error: StateError('bug in the app'),
        ),
        fetcher: env.fetcher,
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      final record = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(record.error?.code, DownloadErrorCode.unknown);
      expect(env.logger.errors, contains(isA<StateError>()));
    },
  );

  test('a link that runs out before the turn is refreshed before the source '
      'is read', () async {
    final refresher = FakeRefresher(
      SourceRequest(url: dashUrl('fresh')),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final engine = await env.engine(refresher: refresher);
    // Inside the margin the download needs to finish.
    final (:id, outcome: _) = await engine.enqueue(
      request(expiresAt: DateTime.now().add(const Duration(minutes: 10))),
    );
    await waitForStatus(engine, id, DownloadStatus.downloading);

    expect(refresher.calls, hasLength(1));
    expect(env.fetcher.requested.map((u) => u.toString()), [dashUrl('fresh')]);
    expect(engine.byId(id)!.expiresAt, refresher.expiresAt);
  });

  test('a link far from expiring is not refreshed', () async {
    final refresher = FakeRefresher(SourceRequest(url: dashUrl('fresh')));
    final engine = await env.engine(refresher: refresher);
    final (:id, outcome: _) = await engine.enqueue(
      request(expiresAt: DateTime.now().add(const Duration(hours: 5))),
    );
    await waitForStatus(engine, id, DownloadStatus.downloading);
    expect(refresher.calls, isEmpty);
  });

  test(
    'without a refresher an expired link just tries the stored source',
    () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);

      expect(env.fetcher.requested.map((u) => u.toString()), [dashUrl()]);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    },
  );

  test('without a refresher, the retry of a dead link reads the stored '
      'source again and keeps what lines up', () async {
    final engine = await env.engine();
    final id = await refusedAfterTwo(engine);
    env.fetcher.requested.clear();

    env.transfer.enqueued.clear();
    await engine.retry(id);
    await waitUntil(() => env.transfer.enqueued.length == 4);
    expect(env.fetcher.requested.map((u) => u.toString()), [dashUrl()]);
  });

  test('a piece the server says is gone is a dead link too', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    env.transfer.emit(
      TaskStatusUpdate(env.transfer.enqueued.first, TaskStatus.notFound),
    );
    final record = await waitForStatus(engine, id, DownloadStatus.failed);
    expect(record.error?.httpStatus, 404);
    expect(record.linkDead, isTrue);
  });

  test('a delete while the refresher answers writes nothing', () async {
    final refresher = _HeldRefresher(SourceRequest(url: dashUrl('fresh')));
    final engine = await env.engine(refresher: refresher);
    final (:id, outcome: _) = await engine.enqueue(
      request(expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
    );
    await waitUntil(() => refresher.waiting);

    await engine.delete(id);
    refresher.release();
    await settle();

    expect(engine.byId(id), isNull);
    expect(Directory(env.work(id)).existsSync(), isFalse);
    expect(env.fetcher.requested, isEmpty);
  });

  test('a fresh link after a kill cancels the tasks still carrying the old '
      'one', () async {
    final refresher = FakeRefresher(SourceRequest(url: dashUrl('fresh')));
    final engine = await env.engine(refresher: refresher);
    final id = await refusedAfterTwo(engine);
    final stale = DownloadTask(
      // Of the first run, with the old link.
      taskId: 'ode-$id-1-0-2',
      url: '$cdn/v720/2.m4s?t=first',
      directory: p.join('haul', id, 't0'),
    );
    env.transfer.inFlight[stale.taskId] = stale;

    await engine.retry(id);
    await waitForStatus(engine, id, DownloadStatus.downloading);
    expect(env.transfer.canceledIds, contains(stale.taskId));
  });
}

class _HeldRefresher implements SourceRefresher {
  _HeldRefresher(this.source);

  final SourceRequest source;
  final _gate = Completer<void>();
  bool waiting = false;

  void release() => _gate.complete();

  @override
  Future<RefreshedSource> refresh(DownloadRecord record) async {
    waiting = true;
    await _gate.future;
    return RefreshedSource(source);
  }
}
