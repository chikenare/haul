import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:path/path.dart' as p;

final _record = DownloadRecord(
  id: 'd1',
  key: 'k',
  title: 'Loki S01E01',
  name: const OutputName(baseName: 'Loki S01E01'),
  status: DownloadStatus.assembling,
  source: const SourceRequest(url: 'https://cdn.example.com/a.mp4'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  late Directory temp;
  late Directory work;
  late Directory downloads;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('output_sinks_test');
    work = await Directory(
      p.join(temp.path, 'work', 'd1'),
    ).create(recursive: true);
    downloads = Directory(p.join(temp.path, 'Downloads'));
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<File> staged([String content = 'movie']) async {
    final file = File(p.join(work.path, 'output.mkv'));
    await file.writeAsString(content);
    return file;
  }

  group('PrivateSink', () {
    test('leaves the file where it is, as a work: locator', () async {
      final file = await staged();
      final locator = await const PrivateSink().publish(
        file,
        _record.name,
        'mkv',
        _record,
      );
      expect(locator, 'work:output.mkv');
      expect(file.existsSync(), isTrue);
    });
  });

  group('DirectorySink', () {
    DirectorySink sink({bool folders = true}) =>
        DirectorySink(() async => downloads.path, folders: folders);

    test('moves the file under its folders', () async {
      final file = await staged();
      final locator = await sink().publish(
        file,
        const OutputName(baseName: 'Loki S01E01', folders: ['Loki', 'S01']),
        'mkv',
        _record,
      );

      expect(locator, p.join(downloads.path, 'Loki', 'S01', 'Loki S01E01.mkv'));
      expect(await File(locator).readAsString(), 'movie');
      expect(file.existsSync(), isFalse);
    });

    test('never over another file', () async {
      const name = OutputName(baseName: 'Movie');
      final first = await sink().publish(
        await staged('1'),
        name,
        'mp4',
        _record,
      );
      final second = await sink().publish(
        await staged('2'),
        name,
        'mp4',
        _record,
      );
      final third = await sink().publish(
        await staged('3'),
        name,
        'mp4',
        _record,
      );

      expect(p.basename(first), 'Movie.mp4');
      expect(p.basename(second), 'Movie (2).mp4');
      expect(p.basename(third), 'Movie (3).mp4');
      expect(await File(first).readAsString(), '1');
      expect(await File(third).readAsString(), '3');
    });

    test('flat when folders are off', () async {
      final locator = await sink(folders: false).publish(
        await staged(),
        const OutputName(baseName: 'Movie', folders: ['A', 'B']),
        'mkv',
        _record,
      );
      expect(p.dirname(locator), downloads.path);
    });

    test('names and folders are made safe; blank folders skipped', () async {
      final locator = await sink().publish(
        await staged(),
        const OutputName(
          baseName: 'What: If...?',
          folders: ['  ', 'AC/DC <Live>'],
        ),
        'mkv',
        _record,
      );
      expect(
        p.relative(locator, from: downloads.path),
        p.join('AC DC Live', 'What If.mkv'),
      );
    });

    test('without a folder the file stays private', () async {
      final file = await staged();
      final locator = await DirectorySink(
        () async => null,
      ).publish(file, _record.name, 'mkv', _record);

      expect(locator, 'work:output.mkv');
      expect(file.existsSync(), isTrue);
      expect(downloads.existsSync(), isFalse);
    });

    test('remove deletes paths only, and a gone file is fine', () async {
      final locator = await sink().publish(
        await staged(),
        _record.name,
        'mkv',
        _record,
      );

      await sink().remove(locator);
      expect(File(locator).existsSync(), isFalse);
      await sink().remove(locator);
      await sink().remove('work:output.mkv');
    });
  });

  group('moveFile', () {
    Future<File> crossVolume(File file, String to) =>
        Future.error(const FileSystemException('Cross-device link'));

    test('copies through a .partial when it cannot rename', () async {
      final file = await staged();
      final to = p.join(temp.path, 'out.mkv');

      await moveFile(file, to, rename: crossVolume);

      expect(await File(to).readAsString(), 'movie');
      expect(file.existsSync(), isFalse);
      expect(File('$to.partial').existsSync(), isFalse);
    });

    test('a failed copy leaves no .partial and keeps the source', () async {
      final file = await staged();
      // A folder in the way: the copy is written and its rename into place
      // fails, as a full card would fail the copy itself.
      final to = p.join(temp.path, 'out.mkv');
      await File(p.join(to, 'taken')).create(recursive: true);

      await expectLater(
        moveFile(file, to, rename: crossVolume),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.existsSync(), isTrue);
      expect(File('$to.partial').existsSync(), isFalse);
    });
  });

  group('safeFileName', () {
    test('replaces what file systems refuse', () {
      expect(safeFileName('a<b>c:d"e/f\\g|h?i*j'), 'a b c d e f g h i j');
      expect(safeFileName('tab\there\nnewline'), 'tab here newline');
    });

    test('trims trailing dots and spaces', () {
      expect(safeFileName('  Movie...  '), 'Movie');
      expect(safeFileName('Mr. Robot'), 'Mr. Robot');
    });

    test('never empty', () {
      expect(safeFileName(''), 'download');
      expect(safeFileName('...'), 'download');
      expect(safeFileName('???', fallback: 'x'), 'x');
    });

    test('Windows device names are not names', () {
      expect(safeFileName('CON'), 'CON_');
      expect(safeFileName('nul'), 'nul_');
      expect(safeFileName('com1.part'), 'com1.part_');
      expect(safeFileName('Console'), 'Console');
    });

    test('at most 150 units, without cutting a character in two', () {
      expect(safeFileName('a' * 200), 'a' * 150);
      // The emoji's two halves straddle the cut.
      final cut = safeFileName('${'a' * 149}😀tail');
      expect(cut, 'a' * 149);
      // A cut that ends in a dot is trimmed again.
      expect(safeFileName('${'a' * 148}. tail'), 'a' * 148);
    });
  });
}
