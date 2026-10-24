import 'dart:io';

import 'package:offline_engine/src/engine/extension_points.dart';
import 'package:offline_engine/src/engine/model.dart';
import 'package:path/path.dart' as p;

/// Leaves the file in the download's own folder, where only the app sees
/// it. Answers a `work:` locator, which the engine resolves itself.
class PrivateSink implements OutputSink {
  const PrivateSink();

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async => 'work:${p.basename(staged.path)}';

  @override
  Future<void> remove(String locator) async {}
}

/// Moves the file into a folder of the user's — their Downloads, or one
/// they picked — under the record's folders, never over another file: a
/// taken name becomes `Name (2).ext`. Without a folder ([root] answers
/// null, or it cannot be written) the file stays private.
class DirectorySink implements OutputSink {
  const DirectorySink(this.root, {this.folders = true});

  final Future<String?> Function() root;

  /// Whether `OutputName.folders` become subfolders (`Loki/Season 01`).
  final bool folders;

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    final base = await root();
    if (base == null) {
      return const PrivateSink().publish(staged, name, extension, record);
    }

    final dir = p.joinAll([
      base,
      if (folders) ...name.folders.map(safeFileName),
    ]);
    await Directory(dir).create(recursive: true);
    final target = await _freePath(dir, safeFileName(name.baseName), extension);
    await _move(staged, target);
    return target;
  }

  @override
  Future<void> remove(String locator) async {
    if (!p.isAbsolute(locator)) return;
    final file = File(locator);
    if (await file.exists()) await file.delete();
  }

  static Future<String> _freePath(
    String dir,
    String base,
    String extension,
  ) async {
    var candidate = p.join(dir, '$base.$extension');
    for (var n = 2; await File(candidate).exists(); n++) {
      candidate = p.join(dir, '$base ($n).$extension');
    }
    return candidate;
  }

  /// A rename on the same volume; otherwise a copy, which is what leaving
  /// application support for external storage takes.
  static Future<void> _move(File from, String to) async {
    try {
      await from.rename(to);
    } on FileSystemException {
      final partial = File('$to.partial');
      await from.copy(partial.path);
      await partial.rename(to);
      await from.delete();
    }
  }
}

/// [name] without what file systems refuse (`<>:"/\|?*`, control
/// characters, trailing dots and spaces), never empty.
String safeFileName(String name, {String fallback = 'download'}) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > 150 ? cleaned.substring(0, 150).trim() : cleaned;
}
