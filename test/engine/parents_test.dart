import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';

import 'engine_test_support.dart';

const _loki = DownloadParent(id: 'show-1', title: 'Loki');

DownloadRecord _record(
  String id, {
  String? title,
  DownloadParent? parent,
  int minute = 0,
  Map<String, Object?> metadata = const {},
}) => DownloadRecord(
  id: id,
  key: id,
  title: title ?? id,
  name: OutputName(baseName: id),
  status: DownloadStatus.queued,
  source: const SourceRequest(url: 'https://cdn.example/a.mpd'),
  parent: parent,
  metadata: metadata,
  createdAt: DateTime.utc(2026, 10, 1, 12, minute),
  updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
);

void main() {
  group('downloadEntries', () {
    test('loose downloads and parents, newest first', () {
      final entries = downloadEntries([
        _record('film-old', minute: 1),
        _record('e1', parent: _loki, minute: 2),
        _record('film-new', minute: 3),
        _record('e2', parent: _loki, minute: 4),
      ]);

      expect(entries, [
        const ParentDownloads(_loki, ['e1', 'e2']),
        const SingleDownload('film-new'),
        const SingleDownload('film-old'),
      ]);
    });

    test('children by title in natural order, not by when they came', () {
      final entries = downloadEntries([
        _record('c', title: 'Loki S01E10', parent: _loki, minute: 1),
        _record('a', title: 'Loki S01E02', parent: _loki, minute: 2),
        _record('b', title: 'Loki S01E03', parent: _loki, minute: 0),
        _record('d', title: 'Loki S02E01', parent: _loki, minute: 3),
      ]);
      expect((entries.single as ParentDownloads).ids, ['a', 'b', 'c', 'd']);
    });

    test('the newest child names the parent', () {
      final entries = downloadEntries([
        _record('e1', parent: _loki, minute: 1),
        _record(
          'e2',
          parent: const DownloadParent(id: 'show-1', title: 'Loki (2021)'),
          minute: 2,
        ),
      ]);
      expect((entries.single as ParentDownloads).parent.title, 'Loki (2021)');
    });
  });

  group('ParentProgress', () {
    DownloadRecord r(DownloadStatus status, {double? fraction}) =>
        _record('x').copyWith(
          status: status,
          progress: DownloadProgress(
            bytes: ((fraction ?? 0) * 100).round(),
            totalBytes: fraction == null ? 0 : 100,
          ),
        );

    test('each child counts the same', () {
      final progress = ParentProgress.of([
        r(DownloadStatus.done),
        r(DownloadStatus.downloading, fraction: 0.5),
        r(DownloadStatus.paused, fraction: 0),
        r(DownloadStatus.failed),
      ]);
      expect(progress.total, 4);
      expect(progress.done, 1);
      expect(progress.active, 1);
      expect(progress.fraction, closeTo(1.5 / 4, 1e-9));
      expect(progress.isActive, isTrue);
      expect(progress.isStopped, isFalse);
      expect(progress.isDone, isFalse);
    });

    test('stopped once nothing moves and something waits', () {
      final progress = ParentProgress.of([
        r(DownloadStatus.done),
        r(DownloadStatus.paused, fraction: 0.2),
      ]);
      expect(progress.isStopped, isTrue);
      expect(ParentProgress.of(const []).isEmpty, isTrue);
      expect(ParentProgress.of([r(DownloadStatus.done)]).isDone, isTrue);
    });
  });

  group('engine', () {
    late Env env;

    setUp(() => env = Env());

    test('keeps the parent and lists its children as one row', () async {
      final engine = await env.engine(json: true);
      await engine.enqueue(
        request(key: 'e2', title: 'Loki S01E02', parent: _loki),
      );
      await engine.enqueue(
        request(key: 'e1', title: 'Loki S01E01', parent: _loki),
      );

      final e1 = engine.byKey('e1')!;
      expect(e1.parent, _loki);
      expect(engine.entries, hasLength(1));
      expect(engine.childrenOf('show-1').map((r) => r.key), ['e1', 'e2']);

      final restored = DownloadRecord.fromJson(
        jsonDecode(jsonEncode(e1.toJson())) as Map<String, Object?>,
      );
      expect(restored, e1);
    });

    test('a record without a parent still reads', () {
      final json = _record('old').toJson()..remove('parent');
      final record = DownloadRecord.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(record.parent, isNull);
    });

    test('entries keep their identity while only progress changes', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(key: 'e1', parent: _loki));
      final before = engine.entries;

      await waitForStatus(engine, first.id, DownloadStatus.downloading);
      expect(identical(engine.entries, before), isTrue);

      await engine.enqueue(request(key: 'film', url: fileUrl));
      expect(identical(engine.entries, before), isFalse);
      expect(engine.entries, hasLength(2));
    });

    test(
      'pause, resume and delete a parent, or some of its children',
      () async {
        final engine = await env.engine();
        final s1 = await engine.enqueue(
          request(key: 's1', parent: _loki, metadata: {'season': 1}),
        );
        final s2 = await engine.enqueue(
          request(key: 's2', parent: _loki, metadata: {'season': 2}),
        );
        final film = await engine.enqueue(request(key: 'film', url: fileUrl));
        bool season1(DownloadRecord r) => r.metadata['season'] == 1;

        await engine.pauseParent('show-1', where: season1);
        expect(engine.byId(s1.id)!.status, DownloadStatus.paused);
        expect(engine.byId(s2.id)!.status, isNot(DownloadStatus.paused));
        expect(
          engine.parentProgress('show-1', where: season1).isStopped,
          isTrue,
        );
        expect(engine.parentProgress('show-1').total, 2);

        await engine.pauseParent('show-1');
        expect(engine.byId(s2.id)!.status, DownloadStatus.paused);
        expect(engine.byId(film.id)!.status, isNot(DownloadStatus.paused));

        await engine.resumeParent('show-1');
        expect(engine.byId(s1.id)!.status, isNot(DownloadStatus.paused));

        await engine.deleteParent('show-1', where: season1);
        expect(
          engine.records.map((r) => r.id),
          unorderedEquals([s2.id, film.id]),
        );

        await engine.deleteParent('show-1');
        expect(engine.records.map((r) => r.id), [film.id]);
        expect(engine.parent('show-1'), isNull);
      },
    );

    test('updateDetails gives an older download its parent', () async {
      final engine = await env.engine();
      final old = await engine.enqueue(request(key: 'e1'));
      expect(engine.byId(old.id)!.parent, isNull);

      await engine.updateDetails(old.id, parent: _loki);
      expect(engine.byId(old.id)!.parent, _loki);
      expect(engine.parent('show-1')!.ids, [old.id]);

      // Only what is given changes.
      await engine.updateDetails(old.id, imageUrl: 'https://img/p.jpg');
      expect(engine.byId(old.id)!.parent, _loki);
      expect(engine.byId(old.id)!.imageUrl, 'https://img/p.jpg');
    });

    test('asking again for a download files it as the request says', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(key: 'e1'));
      final again = await engine.enqueue(request(key: 'e1', parent: _loki));
      expect(again.outcome, EnqueueOutcome.existing);
      expect(engine.byId(first.id)!.parent, _loki);
    });
  });

  group('thumbnails', () {
    late Env env;

    setUp(() => env = Env());

    test('a download without an image gets a frame of itself', () async {
      final thumbnails = FakeThumbnails();
      final engine = await env.engine(thumbnails: thumbnails);
      final result = await engine.enqueue(request(url: fileUrl));
      await env.transfer.completeAll();
      await waitForStatus(engine, result.id, DownloadStatus.done);
      await waitUntil(() => engine.byId(result.id)!.frameLocator != null);

      final record = engine.byId(result.id)!;
      final image = engine.imageOf(record)!;
      expect(File(image).existsSync(), isTrue);
      expect(thumbnails.grabbed.single.path, engine.outputPath(record));
    });

    test('the app image wins, and no frame is taken', () async {
      final thumbnails = FakeThumbnails();
      final engine = await env.engine(thumbnails: thumbnails);
      final result = await engine.enqueue(
        const DownloadRequest(
          key: 'm',
          title: 'm',
          name: OutputName(baseName: 'm'),
          source: SourceRequest(url: fileUrl),
          imageUrl: 'https://img.example/poster.jpg',
        ),
      );
      await env.transfer.completeAll();
      await waitForStatus(engine, result.id, DownloadStatus.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(thumbnails.grabbed, isEmpty);
      expect(
        engine.imageOf(engine.byId(result.id)!),
        'https://img.example/poster.jpg',
      );
    });

    test('a frame that cannot be taken leaves the download done', () async {
      final engine = await env.engine(thumbnails: FakeThumbnails(fail: true));
      final result = await engine.enqueue(request(url: fileUrl));
      await env.transfer.completeAll();
      await waitForStatus(engine, result.id, DownloadStatus.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final record = engine.byId(result.id)!;
      expect(record.status, DownloadStatus.done);
      expect(record.frameLocator, isNull);
      expect(engine.imageOf(record), isNull);
    });
  });
}
