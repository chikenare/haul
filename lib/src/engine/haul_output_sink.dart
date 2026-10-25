import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/output_sinks.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the user wants finished files, as a setting the app keeps (see
/// [toJson]).
@immutable
sealed class HaulDestination {
  const HaulDestination();

  /// Where file managers show it, with no permission asked: on Android the
  /// public Downloads (or Movies) through MediaStore; on desktop the user's
  /// Downloads; on iOS the app's Documents, which the Files app shows when
  /// the app turns file sharing on.
  const factory HaulDestination.public() = PublicDestination;

  /// Only inside the app: nothing else sees it, and it goes with the app.
  const factory HaulDestination.app() = AppDestination;

  /// A folder the user picked: a SAF tree on Android ([HaulFolder.uri]), a
  /// path elsewhere.
  const factory HaulDestination.folder(HaulFolder folder) = FolderDestination;

  factory HaulDestination.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'app' => const AppDestination(),
        'folder' => FolderDestination(
          HaulFolder(
            uri: json['uri']! as String,
            name: json['name'] as String? ?? json['uri']! as String,
          ),
        ),
        _ => const PublicDestination(),
      };

  Map<String, Object?> toJson();
}

final class PublicDestination extends HaulDestination {
  const PublicDestination();

  @override
  Map<String, Object?> toJson() => {'type': 'public'};

  @override
  bool operator ==(Object other) => other is PublicDestination;

  @override
  int get hashCode => 1;
}

final class AppDestination extends HaulDestination {
  const AppDestination();

  @override
  Map<String, Object?> toJson() => {'type': 'app'};

  @override
  bool operator ==(Object other) => other is AppDestination;

  @override
  int get hashCode => 2;
}

final class FolderDestination extends HaulDestination {
  const FolderDestination(this.folder);

  final HaulFolder folder;

  @override
  Map<String, Object?> toJson() => {
    'type': 'folder',
    'uri': folder.uri,
    'name': folder.name,
  };

  @override
  bool operator ==(Object other) =>
      other is FolderDestination && other.folder == folder;

  @override
  int get hashCode => folder.hashCode;
}

/// Moves [file] into the shared [storage] under [directory] and answers
/// its `content://` URI — or its path on Android 9 and older — or null
/// when it could not.
typedef SharedStorageMover =
    Future<String?> Function(
      File file,
      SharedStorage storage,
      String directory,
    );

/// The sink for a [HaulDestination], read when each file is published, so
/// a change in the settings applies to what finishes next.
///
/// On Android a picked folder cannot be written with plain file access:
/// files go through SAF there, and through MediaStore to the public
/// Downloads. When a picked folder can no longer be written (the grant was
/// revoked, the card is out) the file goes public, and when that fails too,
/// it stays in the app — a finished download is never lost to a setting.
class HaulOutputSink implements ReservingOutputSink {
  HaulOutputSink({
    required this.destination,
    this.subfolder = '',
    this.sharedStorage = SharedStorage.downloads,
    HaulAndroid android = HaulAndroid.i,
    SharedStorageMover? moveToShared,
    Future<String?> Function()? publicRoot,
    TargetPlatform? platform,
  }) : _android = android,
       _moveToShared = moveToShared ?? _mediaStoreMove,
       _publicRoot = publicRoot ?? _defaultPublicRoot,
       _platform = platform;

  final Future<HaulDestination> Function() destination;

  /// Under the public folder or a picked one: `MyApp/Videos`. Blank: at
  /// its root.
  final String subfolder;

  /// Android's shared collection for [HaulDestination.public].
  final SharedStorage sharedStorage;

  final HaulAndroid _android;
  final SharedStorageMover _moveToShared;
  final Future<String?> Function() _publicRoot;
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
    final where = await destination();
    if (!_onAndroid) {
      return _directorySink(
        where,
      ).publish(staged, _nested(name), extension, record);
    }
    switch (where) {
      case AppDestination():
        return const PrivateSink().publish(staged, name, extension, record);
      case FolderDestination(:final folder):
        try {
          return await _android.saveToFolder(
            folderUri: folder.uri,
            file: staged,
            relativeName: p.posix.joinAll([
              ..._folders(name),
              '${safeFileName(name.baseName)}.$extension',
            ]),
          );
        } on PlatformException {
          // No grant any more: public, as below.
        } on MissingPluginException {
          // No plugin (tests, another embedding): public, as below.
        }
        return _public(staged, name, extension, record);
      case PublicDestination():
        return _public(staged, name, extension, record);
    }
  }

  Future<String> _public(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
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

  DirectorySink _directorySink(HaulDestination where) => DirectorySink(
    () async => switch (where) {
      AppDestination() => null,
      FolderDestination(:final folder) => folder.uri,
      PublicDestination() => await _publicRoot(),
    },
  );

  @override
  Future<String?> reserve(
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    // Neither SAF nor MediaStore says where a file will go before it is
    // there.
    if (_onAndroid) return null;
    return _directorySink(
      await destination(),
    ).reserve(_nested(name), extension, record);
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
  static Future<String?> _defaultPublicRoot() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await getApplicationDocumentsDirectory()).path;
    }
    return (await getDownloadsDirectory())?.path;
  }
}
