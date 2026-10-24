import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:path/path.dart' as p;

DownloadRecord _record(String id, {String title = 'Movie'}) => DownloadRecord(
  id: id,
  key: 'key-$id',
  title: title,
  name: OutputName(baseName: title),
  status: DownloadStatus.queued,
  source: const SourceRequest(url: 'https://cdn.example.com/a.mp4'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  late Directory root;
  late JsonRecordStore store;

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('record_store_test');
    root = Directory(p.join(temp.path, 'downloads'));
    store = JsonRecordStore(() async => root);
  });

  tearDown(() async {
    await root.parent.delete(recursive: true);
  });

  File recordFile(String id) =>
      File(p.join(root.path, id, JsonRecordStore.recordFile));

  test('nothing to load before the folder exists', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('saves one record.json per download and reads it back', () async {
    final a = _record('a');
    final b = _record('b', title: 'Other');
    await store.save(a);
    await store.save(b);

    final json =
        jsonDecode(await recordFile('a').readAsString())
            as Map<String, Object?>;
    expect(json['v'], 1);
    expect(json['record'], isA<Map<String, Object?>>());
    expect(File('${recordFile('a').path}.tmp').existsSync(), isFalse);

    final loaded = await JsonRecordStore(() async => root).loadAll();
    expect(loaded, unorderedEquals([a, b]));
  });

  test('writes of one id land in order: the last one wins', () async {
    final writes = [
      for (var i = 0; i < 20; i++) store.save(_record('a', title: 'v$i')),
    ];
    await Future.wait(writes);

    final loaded = await store.loadAll();
    expect(loaded.single.title, 'v19');
  });

  test('a failed write does not take the next one down', () async {
    var calls = 0;
    final flaky = JsonRecordStore(() async {
      // The first write's root lookup fails, as a full disk would.
      if (calls++ == 0) throw const FileSystemException('No space left');
      return root;
    });

    final first = flaky.save(_record('a', title: 'first'));
    final second = flaky.save(_record('a', title: 'second'));
    await expectLater(first, throwsA(isA<FileSystemException>()));
    await second;

    expect((await store.loadAll()).single.title, 'second');
  });

  test('delete removes the folder and everything in it', () async {
    await store.save(_record('a'));
    await File(p.join(root.path, 'a', 't0', '0.ts')).create(recursive: true);

    await store.delete('a');

    expect(Directory(p.join(root.path, 'a')).existsSync(), isFalse);
    expect(await store.loadAll(), isEmpty);
    expect(Directory(p.join(root.path, '.trash')).existsSync(), isFalse);
  });

  test('a delete waits for the write in flight', () async {
    unawaited(store.save(_record('a')));
    await store.delete('a');

    expect(Directory(p.join(root.path, 'a')).existsSync(), isFalse);
  });

  test('a write after a delete does not bring the folder back', () async {
    await store.save(_record('a'));
    await store.delete('a');
    await store.save(_record('a', title: 'late'));

    expect(Directory(p.join(root.path, 'a')).existsSync(), isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('deleting what is not there is fine', () async {
    await store.delete('nope');
    await root.create(recursive: true);
    await store.delete('nope');
  });

  test(
    'loadAll drops folders without a record, and the trash, but keeps unreadable records',
    () async {
      await store.save(_record('good'));

      // A kill before the first rename: pieces and no record.
      await File(
        p.join(root.path, 'orphan', 't0', '0.ts'),
      ).create(recursive: true);
      await File(
        p.join(root.path, 'orphan', '${JsonRecordStore.recordFile}.tmp'),
      ).writeAsString('{"v":1,');
      await recordFile('garbage').create(recursive: true);
      await recordFile('garbage').writeAsString('not json');
      await recordFile('wrong-shape').create(recursive: true);
      await recordFile('wrong-shape').writeAsString('{"v":1,"record":{}}');
      await Directory(
        p.join(root.path, '.trash', 'x-1'),
      ).create(recursive: true);
      // Not a folder: not a download either, and not the store's to remove.
      await File(p.join(root.path, 'stray.txt')).writeAsString('x');

      final loaded = await store.loadAll();

      expect(loaded.map((r) => r.id), ['good']);
      final left = root.listSync().map((e) => p.basename(e.path)).toSet();
      // A record it cannot read may be a newer version's: its download stays.
      expect(left, {'good', 'garbage', 'wrong-shape', 'stray.txt'});
    },
  );

  group('MemoryRecordStore', () {
    test('keeps the last save of each id until it is deleted', () async {
      final memory = MemoryRecordStore();
      await memory.save(_record('a'));
      await memory.save(_record('a', title: 'newer'));
      await memory.save(_record('b'));

      expect(
        (await memory.loadAll()).map((r) => r.title),
        unorderedEquals(['newer', 'Movie']),
      );

      await memory.delete('a');
      expect((await memory.loadAll()).map((r) => r.id), ['b']);
    });
  });
}
