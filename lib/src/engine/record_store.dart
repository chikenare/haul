import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:offline_engine/src/engine/model.dart';
import 'package:path/path.dart' as p;

/// Where records live between runs. The engine holds them all in memory and
/// is the only writer; this only has to keep the last write of each.
abstract interface class RecordStore {
  Future<List<DownloadRecord>> loadAll();

  Future<void> save(DownloadRecord record);

  /// The record and everything in its folder.
  Future<void> delete(String id);
}

/// One `record.json` per download, inside the download's own folder: the
/// folder is the download, so a record and its pieces can never disagree
/// about whether it exists. Writes go to a temporary file renamed over the
/// old one, in order per id.
class JsonRecordStore implements RecordStore {
  JsonRecordStore(this._root);

  final Future<Directory> Function() _root;

  static const recordFile = 'record.json';
  static const _trash = '.trash';
  static const _version = 1;

  final Map<String, Future<void>> _writes = {};

  /// Deleted in this run: a write still queued for them must not bring the
  /// folder back.
  final Set<String> _deleted = {};

  /// Every readable record. Folders without one, unreadable ones and what a
  /// delete left in the trash go.
  @override
  Future<List<DownloadRecord>> loadAll() async {
    final root = await _root();
    if (!await root.exists()) return const [];

    final records = <DownloadRecord>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == _trash) {
        await _deleteQuietly(entity);
        continue;
      }
      final record = await _read(File(p.join(entity.path, recordFile)));
      if (record == null) {
        await _deleteQuietly(entity);
      } else {
        records.add(record);
      }
    }
    return records;
  }

  Future<DownloadRecord?> _read(File file) async {
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return DownloadRecord.fromJson(
        (json['record'] as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(DownloadRecord record) {
    final id = record.id;
    final previous = _writes[id] ?? Future<void>.value();
    final write = previous.then((_) => _write(record));
    _writes[id] = write;
    return write.whenComplete(() {
      if (_writes[id] == write) _writes.remove(id);
    });
  }

  Future<void> _write(DownloadRecord record) async {
    if (_deleted.contains(record.id)) return;
    final dir = Directory(p.join((await _root()).path, record.id));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, recordFile));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'v': _version, 'record': record.toJson()}),
      flush: true,
    );
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String id) async {
    _deleted.add(id);
    await _writes[id]?.catchError((Object _) {});
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    if (!await dir.exists()) return;
    // Renamed first, so a half-finished delete is never read back as a
    // download: whatever is left in the trash goes at the next load.
    final trash = Directory(p.join(root.path, _trash));
    await trash.create(recursive: true);
    final target = p.join(
      trash.path,
      '$id-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await _deleteQuietly(await dir.rename(target));
    } on FileSystemException {
      await _deleteQuietly(dir);
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Picked up by the next load.
    }
  }
}

/// For tests and for apps that keep nothing between runs.
class MemoryRecordStore implements RecordStore {
  final Map<String, DownloadRecord> records = {};

  @override
  Future<List<DownloadRecord>> loadAll() async => records.values.toList();

  @override
  Future<void> save(DownloadRecord record) async => records[record.id] = record;

  @override
  Future<void> delete(String id) async => records.remove(id);
}
