import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/output_sinks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Moves [file] into the shared [storage] under [directory] and answers
/// its `content://` URI — or its path on Android 9 and older — or null
/// when it could not.
typedef SharedStorageMover =
    Future<String?> Function(
      File file,
      SharedStorage storage,
      String directory,
    );

/// Where finished files go: into the folder the app gives as [folder] —
/// the one the user picked in the app — or, while it answers null, the
/// platform's default, which needs no permission: on Android the public
/// Downloads through MediaStore, on desktop the user's Downloads, on iOS
/// the app's Documents. Read at each publish, so a change applies to what
/// finishes next.
///
/// When the folder cannot be written to (the card is out, Android refuses
/// a folder outside the ones an app may write by path) the file goes to the
/// default, and when that fails too it stays in the app — a finished
/// download is never lost to a setting.
class HaulOutputSink implements ReservingOutputSink {
  HaulOutputSink({
    this.folder,
    this.subfolder = '',
    this.sharedStorage = SharedStorage.downloads,
    HaulAndroid android = HaulAndroid.i,
    SharedStorageMover? moveToShared,
    @visibleForTesting Future<String?> Function()? defaultFolder,
    TargetPlatform? platform,
  }) : _android = android,
       _moveToShared = moveToShared ?? _mediaStoreMove,
       _defaultFolder = defaultFolder ?? _platformDefault,
       _platform = platform;

  /// A path; null: the default.
  final Future<String?> Function()? folder;

  /// Under the folder: `MyApp/Videos`. Blank: at its root.
  final String subfolder;

  /// Android's shared collection for the default.
  final SharedStorage sharedStorage;

  final HaulAndroid _android;
  final SharedStorageMover _moveToShared;

  /// The default off Android.
  final Future<String?> Function() _defaultFolder;
  final TargetPlatform? _platform;

  bool get _onAndroid =>
      (_platform ?? defaultTargetPlatform) == TargetPlatform.android;

  List<String> _folders(OutputName name) => [
    ...p.posix.split(subfolder).where((s) => s.trim().isNotEmpty && s != '.'),
    for (final folder in name.folders)
      if (folder.trim().isNotEmpty) safeFileName(folder),
  ];

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    if (await folder?.call() case final dir?) {
      try {
        return await DirectorySink(
          () async => dir,
        ).publish(staged, _nested(name), extension, record);
      } on FileSystemException {
        // Not writable: the default, below.
      }
    }
    return _toDefault(staged, name, extension, record);
  }

  Future<String> _toDefault(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    if (!_onAndroid) {
      try {
        return await DirectorySink(
          _defaultFolder,
        ).publish(staged, _nested(name), extension, record);
      } on FileSystemException {
        return const PrivateSink().publish(staged, name, extension, record);
      }
    }
    // MediaStore names the entry after the file: it is renamed to what the
    // user should see first, beside the staged one.
    final named = File(
      p.join(staged.parent.path, '${safeFileName(name.baseName)}.$extension'),
    );
    final renamed = named.path != staged.path;
    if (renamed) await staged.rename(named.path);
    String? shared;
    try {
      shared = await _moveToShared(
        named,
        sharedStorage,
        p.posix.joinAll(_folders(name)),
      );
    } on Object {
      shared = null;
    }
    if (shared != null) return shared;

    // Not published: the staged name comes back so a retry finds it, and
    // the file stays in the app.
    if (renamed) await named.rename(staged.path);
    return const PrivateSink().publish(staged, name, extension, record);
  }

  /// [name] with [subfolder] in front of its folders.
  OutputName _nested(OutputName name) => name.copyWith(folders: _folders(name));

  @override
  Future<String?> reserve(
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    final dir = await folder?.call();
    // MediaStore does not say where a file will go before it is there.
    if (dir == null && _onAndroid) return null;
    try {
      final root = dir ?? await _defaultFolder();
      if (root == null) return null;
      // Made now: a folder that cannot be written answers here, not when
      // the file is moved to its reserved place.
      await Directory(root).create(recursive: true);
      return await DirectorySink(
        () async => root,
      ).reserve(_nested(name), extension, record);
    } on FileSystemException {
      // Not writable: publish decides where it goes instead.
      return null;
    }
  }

  @override
  Future<String> publishTo(
    File staged,
    String locator,
    DownloadRecord record,
  ) => DirectorySink(() async => null).publishTo(staged, locator, record);

  @override
  Future<bool> holds(String locator) async {
    if (HaulAndroid.isContentUri(locator)) return _android.exists(locator);
    return p.isAbsolute(locator) && await File(locator).exists();
  }

  @override
  Future<void> remove(String locator) async {
    if (HaulAndroid.isContentUri(locator)) return _android.delete(locator);
    if (!p.isAbsolute(locator)) return;
    final file = File(locator);
    if (await file.exists()) await file.delete();
  }

  static Future<String?> _mediaStoreMove(
    File file,
    SharedStorage storage,
    String directory,
  ) async {
    final uri = await FileDownloader().uri.moveFileToSharedStorage(
      file.uri,
      storage,
      directory: directory,
    );
    return switch (uri) {
      null => null,
      // Android 9 and older answer the path it moved to.
      Uri(scheme: 'file') => uri.toFilePath(),
      _ => uri.toString(),
    };
  }

  /// The user's Downloads on desktop; the app's Documents on iOS.
  static Future<String?> _platformDefault() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await getApplicationDocumentsDirectory()).path;
    }
    return (await getDownloadsDirectory())?.path;
  }
}
