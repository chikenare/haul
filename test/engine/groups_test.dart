import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/src/engine/groups.dart' show compareSections;
import 'package:haul/testing.dart';

import 'engine_test_support.dart';

const _loki = DownloadGroup(id: 'show-1', title: 'Loki');

DownloadRecord _record(
  String id, {
  DownloadGroup? group,
  String? section,
  num? order,
  int minute = 0,
}) => DownloadRecord(
  id: id,
  key: id,
  title: id,
  name: OutputName(baseName: id),
  status: DownloadStatus.queued,
  source: const SourceRequest(url: 'https://cdn.example/a.mpd'),
  group: group,
  section: section,
  order: order,
  createdAt: DateTime.utc(2026, 10, 1, 12, minute),
  updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
);

void main() {
  group('downloadEntries', () {
    test('loose downloads and groups, newest first', () {
      final entries = downloadEntries([
        _record('film-old', minute: 1),
        _record('e1', group: _loki, minute: 2),
        _record('film-new', minute: 3),
        _record('e2', group: _loki, minute: 4),
      ]);

      expect(entries, [
        const GroupedDownloads(_loki, [
          DownloadSection(null, ['e1', 'e2']),
        ]),
        const SingleDownload('film-new'),
        const SingleDownload('film-old'),
      ]);
    });

    test('sections in natural order, downloads by order then age', () {
      final entries = downloadEntries([
        _record('s10e1', group: _loki, section: '10', order: 1),
        _record('s2e2', group: _loki, section: '2', order: 2, minute: 1),
        _record('s2e1', group: _loki, section: '2', order: 1, minute: 2),
        _record('s2-late', group: _loki, section: '2', minute: 3),
        _record('s2-early', group: _loki, section: '2', minute: 4),
        _record('extra', group: _loki, minute: 5),
      ]);

      final group = entries.single as GroupedDownloads;
      expect(group.sections, const [
        DownloadSection(null, ['extra']),
        DownloadSection('2', ['s2e1', 's2e2', 's2-late', 's2-early']),
        DownloadSection('10', ['s10e1']),
      ]);
      expect(group.ids.first, 'extra');
    });

    test('the newest download names the group', () {
      final entries = downloadEntries([
        _record('e1', group: _loki, minute: 1),
        _record(
          'e2',
          group: const DownloadGroup(id: 'show-1', title: 'Loki (2021)'),
          minute: 2,
        ),
      ]);

      expect((entries.single as GroupedDownloads).group.title, 'Loki (2021)');
    });

    test('compareSections: null, numbers, then words', () {
      final sections = <String?>['b', '10', null, 'a', '2', '1.5']
        ..sort(compareSections);
      expect(sections, [null, '1.5', '2', '10', 'a', 'b']);
    });
  });

  group('engine', () {
    late Env env;

    setUp(() => env = Env());

    test('keeps the group fields and lists them as one entry', () async {
      final engine = await env.engine(json: true);
      await engine.enqueue(
        request(key: 'e1', group: _loki, section: '1', order: 1),
      );
      await engine.enqueue(
        request(key: 'e2', group: _loki, section: '1', order: 2),
      );

      final e1 = engine.byKey('e1')!;
      expect(e1.group, _loki);
      expect(e1.section, '1');
      expect(e1.order, 1);
      expect(engine.entries, hasLength(1));
      expect(engine.group('show-1')!.ids, [e1.id, engine.byKey('e2')!.id]);

      final restored = DownloadRecord.fromJson(
        jsonDecode(jsonEncode(e1.toJson())) as Map<String, Object?>,
      );
      expect(restored, e1);
    });

    test('a record without group fields still reads', () {
      final json = _record('old').toJson()
        ..remove('group')
        ..remove('section')
        ..remove('order')
        ..remove('imageUrl');
      final record = DownloadRecord.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(record.group, isNull);
      expect(record.order, isNull);
    });

    test('entries keep their identity while only progress changes', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(key: 'e1', group: _loki));
      final before = engine.entries;

      await waitForStatus(engine, first.id, DownloadStatus.downloading);
      expect(identical(engine.entries, before), isTrue);

      await engine.enqueue(request(key: 'film', url: fileUrl));
      expect(identical(engine.entries, before), isFalse);
      expect(engine.entries, hasLength(2));
    });

    test(
      'pauseGroup, resumeGroup and deleteGroup act on its downloads',
      () async {
        final engine = await env.engine();
        final e1 = await engine.enqueue(request(key: 'e1', group: _loki));
        final e2 = await engine.enqueue(request(key: 'e2', group: _loki));
        final film = await engine.enqueue(request(key: 'film', url: fileUrl));

        await engine.pauseGroup('show-1');
        expect(engine.byId(e1.id)!.status, DownloadStatus.paused);
        expect(engine.byId(e2.id)!.status, DownloadStatus.paused);
        expect(engine.byId(film.id)!.status, isNot(DownloadStatus.paused));

        await engine.resumeGroup('show-1');
        expect(engine.byId(e1.id)!.status, isNot(DownloadStatus.paused));
        expect(engine.byId(e2.id)!.status, isNot(DownloadStatus.paused));

        await engine.deleteGroup('show-1');
        expect(engine.records.map((r) => r.id), [film.id]);
        expect(engine.group('show-1'), isNull);
      },
    );
  });

  group('GroupProgress', () {
    DownloadRecord r(DownloadStatus status, {double? fraction}) =>
        _record('x').copyWith(
          status: status,
          progress: DownloadProgress(
            bytes: ((fraction ?? 0) * 100).round(),
            totalBytes: fraction == null ? 0 : 100,
          ),
        );

    test('each download counts the same', () {
      final progress = GroupProgress.of([
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
      final progress = GroupProgress.of([
        r(DownloadStatus.done),
        r(DownloadStatus.paused, fraction: 0.2),
      ]);
      expect(progress.isStopped, isTrue);
      expect(GroupProgress.of(const []).isEmpty, isTrue);
      expect(GroupProgress.of([r(DownloadStatus.done)]).isDone, isTrue);
    });
  });

  group('details', () {
    late Env env;

    setUp(() => env = Env());

    test('updateDetails files an older download under a group', () async {
      final engine = await env.engine();
      final old = await engine.enqueue(request(key: 'e1'));
      expect(engine.byId(old.id)!.group, isNull);

      await engine.updateDetails(old.id, group: _loki, section: '1', order: 3);
      final record = engine.byId(old.id)!;
      expect(record.group, _loki);
      expect(record.section, '1');
      expect(record.order, 3);
      expect(engine.group('show-1')!.ids, [old.id]);

      // Only what is given changes.
      await engine.updateDetails(old.id, order: 4);
      expect(engine.byId(old.id)!.section, '1');
      expect(engine.byId(old.id)!.order, 4);
    });

    test('asking again for a download files it as the request says', () async {
      final engine = await env.engine();
      final first = await engine.enqueue(request(key: 'e1'));
      final again = await engine.enqueue(
        request(key: 'e1', group: _loki, section: '2'),
      );
      expect(again.outcome, EnqueueOutcome.existing);
      expect(engine.byId(first.id)!.group, _loki);
      expect(engine.byId(first.id)!.section, '2');
    });

    test('group progress and actions by section', () async {
      final engine = await env.engine();
      final s1 = await engine.enqueue(
        request(key: 's1', group: _loki, section: '1'),
      );
      final s2 = await engine.enqueue(
        request(key: 's2', group: _loki, section: '2'),
      );

      await engine.pauseGroup('show-1', section: '1');
      expect(engine.byId(s1.id)!.status, DownloadStatus.paused);
      expect(engine.byId(s2.id)!.status, isNot(DownloadStatus.paused));
      expect(engine.groupProgress('show-1', section: '1').isStopped, isTrue);
      expect(engine.groupProgress('show-1').total, 2);

      await engine.deleteGroup('show-1', section: '1');
      expect(engine.records.map((r) => r.id), [s2.id]);
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
        DownloadRequest(
          key: 'm',
          title: 'm',
          name: const OutputName(baseName: 'm'),
          source: const SourceRequest(url: fileUrl),
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
