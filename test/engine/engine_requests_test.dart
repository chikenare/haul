import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_engine/offline_engine.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;

  setUp(() => env = Env());

  Future<DownloadPlan> planOf(String url, TrackCriteria criteria) async {
    final source = await SourceResolver(
      fetcher: env.fetcher,
    ).resolve(SourceRequest(url: url));
    return source.plan(source.selectionFor(criteria));
  }

  List<String?> audioLanguages(String id) => [
    for (final t in env.plan(id).tracks)
      if (t.kind == TrackKind.audio) t.language,
  ];

  group('enqueue', () {
    test('the same key twice finds the first', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request());
      final second = await engine.enqueue(request(url: fileUrl));

      expect(second, (id: first.id, outcome: EnqueueOutcome.existing));
      expect(engine.records, hasLength(1));
      expect(engine.byKey('movie-1')!.source.url, dashUrl());
    });

    test('a failed one starts again with the new source, same id', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(url: '$cdn/missing.mpd'));
      await waitForStatus(engine, first.id, DownloadStatus.failed);

      final again = await engine.enqueue(
        request(title: 'Otra', metadata: {'v': 2}),
      );
      expect(again, (id: first.id, outcome: EnqueueOutcome.replacedFailed));

      await waitUntil(() => env.transfer.enqueued.length == 6);
      final record = engine.byId(first.id)!;
      expect(record.status, DownloadStatus.downloading);
      expect(record.source.url, dashUrl());
      expect(record.title, 'Otra');
      expect(record.metadata, {'v': 2});
      expect(record.error, isNull);
    });

    test('enqueueAll answers one result per request', () async {
      final engine = await env.engine();
      final results = await engine.enqueueAll([
        request(key: 'a'),
        request(key: 'b'),
        request(key: 'a'),
      ]);
      expect(results.map((r) => r.outcome), [
        EnqueueOutcome.created,
        EnqueueOutcome.created,
        EnqueueOutcome.existing,
      ]);
      expect(results[2].id, results[0].id);
    });

    test('a ready plan is used without reading the source', () async {
      final plan = await planOf(dashUrl(), englishCriteria);
      env.fetcher.requested.clear();
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(plan: plan));
      await waitUntil(() => env.transfer.enqueued.length == 6);

      expect(env.fetcher.requested, isEmpty);
      expect(audioLanguages(id), ['en']);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    });

    test(
      'the same key with a plan, twice at once, is still one record',
      () async {
        final plan = await planOf(dashUrl(), latinCriteria);
        final engine = await env.engine();
        final results = await Future.wait([
          engine.enqueue(request(plan: plan)),
          engine.enqueue(request(plan: plan)),
        ]);

        expect(engine.records, hasLength(1));
        expect(results.map((r) => r.outcome).toSet(), {
          EnqueueOutcome.created,
          EnqueueOutcome.existing,
        });
        expect(results[0].id, results[1].id);
      },
    );

    test('a failed one asked again with a plan that lines up keeps its '
        'pieces; one that does not wipes them', () async {
      final latin = await planOf(dashUrl(), latinCriteria);
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request(plan: latin));
      await waitUntil(() => env.transfer.enqueued.length == 6);
      final kept = env.transfer.enqueued.first;
      await env.transfer.complete(kept);
      env.transfer.fail(env.transfer.enqueued.last);
      await waitForStatus(engine, id, DownloadStatus.failed);

      env.transfer.enqueued.clear();
      await engine.enqueue(request(plan: latin));
      await waitUntil(() => env.transfer.enqueued.length == 5);
      expect(env.transfer.fileOf(kept).existsSync(), isTrue);

      env.transfer.fail(env.transfer.enqueued.last);
      await waitForStatus(engine, id, DownloadStatus.failed);
      env.transfer.enqueued.clear();
      await engine.enqueue(
        request(plan: await planOf(dashUrl(), englishCriteria)),
      );
      await waitUntil(() => env.transfer.enqueued.length == 6);
      expect(env.transfer.fileOf(kept).existsSync(), isFalse);
    });
  });

  group('track choice', () {
    test('policy reads the criteria when the turn comes, not before', () async {
      var criteria = latinCriteria;
      final asked = <String>[];
      final engine = await env.engine(
        criteria: (record) async {
          asked.add(record.key);
          return criteria;
        },
      );
      final first = await engine.enqueue(request(key: 'a'));
      final second = await engine.enqueue(request(key: 'b'));
      await waitUntil(() => env.transfer.enqueued.length == 6);
      expect(asked, ['a']);

      // The user changes the settings while the first one downloads.
      criteria = englishCriteria;
      await env.transfer.completeAll();
      await waitForStatus(engine, first.id, DownloadStatus.done);
      await waitUntil(() => env.planFile(second.id).existsSync());

      expect(asked, ['a', 'b']);
      expect(audioLanguages(first.id), ['es-419']);
      expect(audioLanguages(second.id), ['en']);
    });

    test('criteria are the request\'s own', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(tracks: const TrackChoice.criteria(englishCriteria)),
      );
      await waitForStatus(engine, id, DownloadStatus.downloading);
      expect(audioLanguages(id), ['en']);
    });

    test('a selection is kept while the source still has it', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(
          tracks: const TrackChoice.selection(
            SourceSelection(videoId: 'v720', audioIds: {'a-en', 'a-lat'}),
          ),
        ),
      );
      await waitForStatus(engine, id, DownloadStatus.downloading);
      expect(audioLanguages(id), ['es-419', 'en']);
    });

    test('a selection whose ids are gone falls back to its criteria', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(
          tracks: const TrackChoice.selection(
            SourceSelection(videoId: 'v720', audioIds: {'a-gone'}),
            fallback: englishCriteria,
          ),
        ),
      );
      await waitForStatus(engine, id, DownloadStatus.downloading);
      expect(audioLanguages(id), ['en']);
    });

    test(
      'a refresher that changes the metadata is what the criteria see',
      () async {
        final seen = <Map<String, Object?>>[];
        final engine = await env.engine(
          refresher: FakeRefresher(
            SourceRequest(url: dashUrl('fresh')),
            metadata: {'fresh': true},
          ),
          criteria: (record) async {
            seen.add(record.metadata);
            return latinCriteria;
          },
        );
        final (:id, outcome: _) = await engine.enqueue(
          request(
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            metadata: {'fresh': false},
          ),
        );
        await waitForStatus(engine, id, DownloadStatus.downloading);
        expect(seen, [
          {'fresh': true},
        ]);
      },
    );
  });

  group('subtitles', () {
    const withSubtitles = TrackChoice.criteria(
      TrackCriteria(audio: LanguageTracks(['es-419'])),
    );

    test('sidecars stay beside a merged file', () async {
      final out = Directory(p.join(env.dir.path, 'Movies'));
      final engine = await env.engine(
        sink: DirectorySink(() async => out.path),
      );
      final (:id, outcome: _) = await engine.enqueue(
        request(
          tracks: withSubtitles,
          subtitles: {'Español': subtitleUrl},
          output: const OutputMode(
            kind: OutputKind.file,
            subtitleSidecars: true,
          ),
        ),
      );
      await waitUntil(() => env.transfer.enqueued.length == 7);
      expect(await engine.subtitlesOf(id), isEmpty);

      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);

      final subtitles = await engine.subtitlesOf(id);
      expect(subtitles, hasLength(1));
      expect(subtitles.single.label, 'Español');
      expect(p.isWithin(env.work(id), subtitles.single.path), isTrue);
      expect(File(subtitles.single.path).existsSync(), isTrue);
      // And they went into the MKV too.
      expect(env.ffmpeg.runs.single.join(' '), contains('0.vtt'));
    });

    test('without sidecars, none are kept', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(
          tracks: withSubtitles,
          subtitles: {'Español': subtitleUrl},
          output: OutputMode.file,
        ),
      );
      await waitUntil(() => env.transfer.enqueued.length == 7);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);

      expect(await engine.subtitlesOf(id), isEmpty);
    });

    test("a package's subtitles are listed", () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(
        request(tracks: withSubtitles, subtitles: {'Español': subtitleUrl}),
      );
      await waitUntil(() => env.transfer.enqueued.length == 7);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);

      final subtitles = await engine.subtitlesOf(id);
      expect(subtitles.single.path, p.join(env.work(id), 't2', '0.vtt'));
      expect(await engine.subtitlesOf('unknown'), isEmpty);
    });
  });

  group('streams', () {
    test('watchAll emits a snapshot on every change, in order', () async {
      final engine = await env.engine();
      final seen = <DownloadStatus>[];
      final sub = engine.watchAll().listen((records) {
        final status = records.firstOrNull?.status;
        if (status != null && seen.lastOrNull != status) seen.add(status);
      });
      addTearDown(sub.cancel);
      await settle();

      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
      await settle();

      expect(seen, [
        DownloadStatus.queued,
        DownloadStatus.resolving,
        DownloadStatus.downloading,
        DownloadStatus.assembling,
        DownloadStatus.done,
      ]);
    });

    test('watch follows one record until it is deleted', () async {
      final engine = await env.engine();
      final (:id, outcome: _) = await engine.enqueue(request());
      final seen = <DownloadRecord?>[];
      final sub = engine.watch(id).listen(seen.add);
      addTearDown(sub.cancel);
      await waitUntil(() => seen.isNotEmpty);

      await engine.delete(id);
      await waitUntil(() => seen.last == null);
      expect(seen.first?.id, id);
    });

    test('records are newest first', () async {
      final engine = await env.engine();
      final a = await engine.enqueue(request(key: 'a'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = await engine.enqueue(request(key: 'b'));
      expect(engine.records.map((r) => r.id), [b.id, a.id]);
    });

    test('progress is throttled per download', () async {
      final engine = await env.engine(
        config: const EngineConfig(progressInterval: Duration(hours: 1)),
      );
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      final task = env.transfer.enqueued.single;
      var emissions = 0;
      final sub = engine.watchAll().skip(1).listen((_) => emissions++);
      addTearDown(sub.cancel);
      await settle();

      for (final fraction in [0.1, 0.5, 0.9]) {
        env.transfer.emitProgress(TaskProgressUpdate(task, fraction, 1000));
      }
      await settle();

      expect(emissions, 1);
      expect(engine.byId(id)!.progress.bytes, 100);
      expect(engine.byId(id)!.progress.fraction, closeTo(0.1, 1e-9));
    });

    test('progress without a throttle follows every update', () async {
      final engine = await env.engine(
        config: const EngineConfig(progressInterval: Duration.zero),
      );
      final (:id, outcome: _) = await engine.enqueue(request(url: fileUrl));
      await waitUntil(() => env.transfer.enqueued.length == 1);
      final task = env.transfer.enqueued.single;

      for (final fraction in [0.1, 0.5, 0.9]) {
        env.transfer.emitProgress(TaskProgressUpdate(task, fraction, 1000));
      }
      expect(engine.byId(id)!.progress.bytes, 900);
      // Updates of tasks the engine does not follow are ignored.
      env.transfer.emitProgress(
        TaskProgressUpdate(task.copyWith(taskId: 'other'), 0.5, 1000),
      );
      expect(engine.byId(id)!.progress.bytes, 900);
    });
  });

  test(
    'a delete while a fresh plan reads its playlists leaves no folder',
    () async {
      final gate = _PlaylistGate(env.fetcher);
      final engine = await env.engine(
        fetcher: gate,
        refresher: FakeRefresher(const SourceRequest(url: hlsUrl)),
      );
      final (:id, outcome: _) = await engine.enqueue(request(url: hlsUrl));
      await waitUntil(() => env.transfer.enqueued.length == 4);
      env.transfer.fail(env.transfer.enqueued.first, httpStatus: 403);
      await waitForStatus(engine, id, DownloadStatus.failed);

      gate.hold = true;
      await engine.retry(id);
      await waitUntil(() => gate.waiting);
      await engine.delete(id);
      gate.release();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(engine.byId(id), isNull);
      expect(Directory(env.work(id)).existsSync(), isFalse);
    },
  );
}

/// Once [hold] is set, holds media playlist reads until [release].
class _PlaylistGate extends SourceFetcher {
  _PlaylistGate(this.inner);

  final SourceFetcher inner;
  bool hold = false;
  bool waiting = false;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    if (hold && !url.path.endsWith('master.m3u8')) {
      waiting = true;
      await _gate.future;
    }
    return inner.fetch(url, headers: headers, maxBytes: maxBytes);
  }
}
