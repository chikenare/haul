import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/src/engine/groups.dart' show compareSections;

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
}
