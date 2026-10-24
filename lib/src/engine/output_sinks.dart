import 'dart:io';

import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/model.dart';
import 'package:meta/meta.dart';
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
/// null) the file stays private; a folder that cannot be written fails the
/// publish, so the user is told rather than finding the file elsewhere.
class DirectorySink implements ReservingOutputSink {
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
    final target = await reserve(name, extension, record);
    if (target == null) {
      return const PrivateSink().publish(staged, name, extension, record);
    }
    return publishTo(staged, target, record);
  }

  @override
  Future<String?> reserve(
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    final base = await root();
    if (base == null) return null;
    final dir = p.joinAll([
      base,
      // A blank folder is no level at all, not one called `download`.
      if (folders)
        for (final folder in name.folders)
          if (folder.trim().isNotEmpty) safeFileName(folder),
    ]);
    return _freePath(dir, safeFileName(name.baseName), extension);
  }

  @override
  Future<String> publishTo(
    File staged,
    String locator,
    DownloadRecord record,
  ) async {
    await Directory(p.dirname(locator)).create(recursive: true);
    // Taken since it was reserved (a retry after a failed move, or someone
    // else's file): never over it.
    final target = await File(locator).exists()
        ? await _freePath(
            p.dirname(locator),
            p.basenameWithoutExtension(locator),
            p.extension(locator).replaceFirst('.', ''),
          )
        : locator;
    await _move(staged, target);
    return target;
  }

  @override
  Future<bool> holds(String locator) async =>
      p.isAbsolute(locator) && await File(locator).exists();

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

  static Future<void> _move(File from, String to) => moveFile(from, to);
}

/// A rename on the same volume; otherwise a copy, which is what leaving
/// application support for external storage takes. The copy goes to a
/// `.partial` that is removed when it fails — a full card would otherwise
/// leave half a movie in the user's folder — and [from] stays for a retry.
@visibleForTesting
Future<void> moveFile(
  File from,
  String to, {
  Future<File> Function(File file, String to)? rename,
}) async {
  final doRename = rename ?? (file, to) => file.rename(to);
  try {
    await doRename(from, to);
  } on FileSystemException {
    final partial = File('$to.partial');
    try {
      await from.copy(partial.path);
      await partial.rename(to);
    } on Object {
      try {
        if (await partial.exists()) await partial.delete();
      } on FileSystemException {
        // Nothing more to do; the error below is what matters.
      }
      rethrow;
    }
    // The file is in place: a source that cannot go (locked on Windows)
    // must not fail a publish that worked. It goes with the work folder.
    try {
      await from.delete();
    } on FileSystemException {
      // Left behind.
    }
  }
}

/// [name] without what file systems refuse (`<>:"/\|?*`, control
/// characters, trailing dots and spaces, Windows device names), never empty.
String safeFileName(String name, {String fallback = 'download'}) {
  String trimEnd(String s) => s.trim().replaceAll(RegExp(r'[. ]+$'), '');

  var cleaned = trimEnd(
    name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' '),
  );
  if (cleaned.length > _maxNameLength) {
    var end = _maxNameLength;
    // Not between the two halves of a surrogate pair: half an emoji is not
    // a valid name on every file system.
    if (_isHighSurrogate(cleaned.codeUnitAt(end - 1))) end--;
    // Trimmed again: the cut may end in a dot or a space.
    cleaned = trimEnd(cleaned.substring(0, end));
  }
  if (cleaned.isEmpty) return fallback;
  // Windows opens the device for `CON`, `NUL`, `COM1`… even with an
  // extension, so `NUL.mkv` is not a file there.
  if (_windowsDevices.hasMatch(cleaned.split('.').first)) return '${cleaned}_';
  return cleaned;
}

const _maxNameLength = 150;

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

final _windowsDevices = RegExp(
  r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])\s*$',
  caseSensitive: false,
);
