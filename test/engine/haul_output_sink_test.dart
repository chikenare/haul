import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
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

const _name = OutputName(
  baseName: 'Loki S01E01',
  folders: ['Loki', 'Season 01'],
);
void main() {
  late Directory temp;
  late Directory work;
  late FakeHaulAndroid android;
  late List<(String, SharedStorage, String)> moved;
  String? movedUri;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('haul_output_sink_test');
    work = await Directory(p.join(temp.path, 'd1')).create(recursive: true);
    android = FakeHaulAndroid();
    moved = [];
    movedUri = 'content://media/external/downloads/7';
  });

  tearDown(() => temp.delete(recursive: true));

  Future<File> staged() async {
    final file = File(p.join(work.path, 'output.mkv'));
    await file.writeAsString('movie');
    return file;
  }

  /// [folder]: the app's path; null, the default (MediaStore on Android,
  /// `Downloads` in the temp folder elsewhere).
  HaulOutputSink sink({
    String? folder,
    TargetPlatform platform = TargetPlatform.android,
  }) => HaulOutputSink(
    folder: () async => folder,
    subfolder: 'App/Videos',
    android: android,
    platform: platform,
    defaultFolder: () async => p.join(temp.path, 'Downloads'),
    moveToShared: (file, storage, directory) async {
      moved.add((p.basename(file.path), storage, directory));
      return movedUri;
    },
  );

  String under(String root) =>
      p.join(root, 'App', 'Videos', 'Loki', 'Season 01', 'Loki S01E01.mkv');

  /// A folder nothing can be written in: a file stands where it would go.
  Future<String> unwritable() async {
    final blocker = File(p.join(temp.path, 'blocked'));
    await blocker.writeAsString('');
    return p.join(blocker.path, 'inside');
  }

  group('on Android', () {
    test(
      'by default: renamed for MediaStore and moved under its folders',
      () async {
        final locator = await sink().publish(
          await staged(),
          _name,
          'mkv',
          _record,
        );

        expect(locator, movedUri);
        expect(moved, [
          (
            'Loki S01E01.mkv',
            SharedStorage.downloads,
            'App/Videos/Loki/Season 01',
          ),
        ]);
      },
    );

    test(
      'MediaStore refused: the staged name comes back, kept in the app',
      () async {
        movedUri = null;
        final file = await staged();
        final locator = await sink().publish(file, _name, 'mkv', _record);

        expect(locator, 'work:output.mkv');
        expect(file.existsSync(), isTrue);
      },
    );

    test("the app's folder: a plain file there, not MediaStore", () async {
      final folder = p.join(temp.path, 'Picked');
      final locator = await sink(
        folder: folder,
      ).publish(await staged(), _name, 'mkv', _record);

      expect(locator, under(folder));
      expect(await File(locator).readAsString(), 'movie');
      expect(moved, isEmpty);
    });

    test('a folder that cannot be written: the default instead', () async {
      final locator = await sink(
        folder: await unwritable(),
      ).publish(await staged(), _name, 'mkv', _record);

      expect(locator, movedUri);
    });

    test(
      'only a folder of the app is known before the file is there',
      () async {
        expect(await sink().reserve(_name, 'mkv', _record), isNull);
        final folder = p.join(temp.path, 'Picked');
        expect(
          await sink(folder: folder).reserve(_name, 'mkv', _record),
          startsWith(folder),
        );
      },
    );

    test('remove and holds go through the plugin for content URIs', () async {
      final s = sink();
      android.existing.add('content://media/1');
      expect(await s.holds('content://media/1'), isTrue);

      await s.remove('content://media/1');
      expect(android.deleted, ['content://media/1']);
      expect(await s.holds('content://media/1'), isFalse);
    });
  });

  group('elsewhere', () {
    test(
      'by default: into Downloads under the subfolder and its folders',
      () async {
        final locator = await sink(
          platform: TargetPlatform.macOS,
        ).publish(await staged(), _name, 'mkv', _record);

        expect(locator, under(p.join(temp.path, 'Downloads')));
        expect(File(locator).existsSync(), isTrue);
        expect(moved, isEmpty);
      },
    );

    test("the app's folder, reserved before the move", () async {
      final folder = p.join(temp.path, 'Picked');
      final s = sink(folder: folder, platform: TargetPlatform.windows);
      final reserved = await s.reserve(_name, 'mkv', _record);
      expect(reserved, startsWith(folder));

      final locator = await s.publishTo(await staged(), reserved!, _record);
      expect(locator, reserved);
      expect(await s.holds(locator), isTrue);

      await s.remove(locator);
      expect(File(locator).existsSync(), isFalse);
    });

    test('a folder that cannot be written: the default instead', () async {
      final s = sink(
        folder: await unwritable(),
        platform: TargetPlatform.linux,
      );
      expect(await s.reserve(_name, 'mkv', _record), isNull);
      expect(
        await s.publish(await staged(), _name, 'mkv', _record),
        under(p.join(temp.path, 'Downloads')),
      );
    });
  });
}
