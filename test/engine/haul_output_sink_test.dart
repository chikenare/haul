import 'dart:convert';
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
const _folder = HaulFolder(
  uri: 'content://tree/primary%3AMovies',
  name: 'Movies',
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

  HaulOutputSink sink(
    HaulDestination destination, {
    TargetPlatform platform = TargetPlatform.android,
  }) => HaulOutputSink(
    destination: () async => destination,
    subfolder: 'App/Videos',
    android: android,
    platform: platform,
    publicRoot: () async => p.join(temp.path, 'Downloads'),
    moveToShared: (file, storage, directory) async {
      moved.add((p.basename(file.path), storage, directory));
      return movedUri;
    },
  );

  group('on Android', () {
    test(
      'public: renamed for MediaStore and moved under its folders',
      () async {
        final locator = await sink(
          const HaulDestination.public(),
        ).publish(await staged(), _name, 'mkv', _record);

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
      'public refused: the staged name comes back, kept in the app',
      () async {
        movedUri = null;
        final file = await staged();
        final locator = await sink(
          const HaulDestination.public(),
        ).publish(file, _name, 'mkv', _record);

        expect(locator, 'work:output.mkv');
        expect(file.existsSync(), isTrue);
      },
    );

    test('app: stays private', () async {
      final locator = await sink(
        const HaulDestination.app(),
      ).publish(await staged(), _name, 'mkv', _record);

      expect(locator, 'work:output.mkv');
      expect(moved, isEmpty);
    });

    test('folder: copied through SAF under its folders', () async {
      final file = await staged();
      final locator = await sink(
        const HaulDestination.folder(_folder),
      ).publish(file, _name, 'mkv', _record);

      expect(android.saved, [
        (_folder.uri, 'App/Videos/Loki/Season 01/Loki S01E01.mkv'),
      ]);
      expect(locator, startsWith(_folder.uri));
      expect(file.existsSync(), isFalse);
    });

    test('folder without a grant: public instead', () async {
      android.revoked.add(_folder.uri);
      final locator = await sink(
        const HaulDestination.folder(_folder),
      ).publish(await staged(), _name, 'mkv', _record);

      expect(locator, movedUri);
      expect(android.saved, isEmpty);
    });

    test('nothing is reserved: neither SAF nor MediaStore can say', () async {
      expect(
        await sink(
          const HaulDestination.public(),
        ).reserve(_name, 'mkv', _record),
        isNull,
      );
    });

    test('remove and holds go through the plugin for content URIs', () async {
      final s = sink(const HaulDestination.public());
      android.existing.add('content://media/1');
      expect(await s.holds('content://media/1'), isTrue);

      await s.remove('content://media/1');
      expect(android.deleted, ['content://media/1']);
      expect(await s.holds('content://media/1'), isFalse);
    });
  });

  group('elsewhere', () {
    test(
      'public: into Downloads under the subfolder and its folders',
      () async {
        final locator = await sink(
          const HaulDestination.public(),
          platform: TargetPlatform.macOS,
        ).publish(await staged(), _name, 'mkv', _record);

        expect(
          locator,
          p.join(
            temp.path,
            'Downloads',
            'App',
            'Videos',
            'Loki',
            'Season 01',
            'Loki S01E01.mkv',
          ),
        );
        expect(File(locator).existsSync(), isTrue);
        expect(moved, isEmpty);
      },
    );

    test('folder: the picked path, reserved before the move', () async {
      final picked = p.join(temp.path, 'Picked');
      final s = sink(
        HaulDestination.folder(HaulFolder(uri: picked, name: picked)),
        platform: TargetPlatform.windows,
      );
      final reserved = await s.reserve(_name, 'mkv', _record);
      expect(reserved, startsWith(picked));

      final locator = await s.publishTo(await staged(), reserved!, _record);
      expect(locator, reserved);
      expect(await s.holds(locator), isTrue);

      await s.remove(locator);
      expect(File(locator).existsSync(), isFalse);
    });

    test('app: private, nothing reserved', () async {
      final s = sink(
        const HaulDestination.app(),
        platform: TargetPlatform.linux,
      );
      expect(await s.reserve(_name, 'mkv', _record), isNull);
      expect(
        await s.publish(await staged(), _name, 'mkv', _record),
        'work:output.mkv',
      );
    });
  });

  test('HaulDestination survives JSON', () {
    for (final d in const [
      HaulDestination.public(),
      HaulDestination.app(),
      HaulDestination.folder(_folder),
    ]) {
      final back = HaulDestination.fromJson(
        jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>,
      );
      expect(back, d);
    }
    expect(HaulDestination.fromJson(const {}), const HaulDestination.public());
  });
}
