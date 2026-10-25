import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

/// A folder the user picked with Android's explorer: written through its
/// [uri] (a SAF tree with a persistent grant), shown as [name].
@immutable
class HaulFolder {
  const HaulFolder({required this.uri, required this.name});

  final String uri;

  /// `Movies/App` on internal storage, `1A2B-3C4D/Videos` on an SD card.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is HaulFolder && other.uri == uri && other.name == name;

  @override
  int get hashCode => Object.hash(uri, name);
}

/// haul's own Android side (`HaulPlugin.kt`): picked folders, finished
/// files behind `content://` URIs, and the battery saver. Off Android every
/// call answers what "nothing to do" means, so callers need no checks.
class HaulAndroid {
  const HaulAndroid({
    MethodChannel channel = const MethodChannel('haul/android'),
    bool? android,
  }) : _channel = channel,
       _android = android;

  static const i = HaulAndroid();

  final MethodChannel _channel;
  final bool? _android;

  bool get isAndroid =>
      _android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static bool isContentUri(String locator) => locator.startsWith('content://');

  /// Opens the explorer, at [initialUri] when given. Null when the user
  /// backs out. Throws [PlatformException] when the provider gives no
  /// persistent grant (`not_persistable`).
  Future<HaulFolder?> pickFolder({String? initialUri}) async {
    if (!isAndroid) return null;
    return _folderOf(
      await _channel.invokeMapMethod<String, String>('pickFolder', {
        'initial': initialUri,
      }),
    );
  }

  /// [uri] with its current name, or null once the grant to write there is
  /// gone (the user revoked it, the SD card is out).
  Future<HaulFolder?> describeFolder(String uri) async {
    if (!isAndroid) return null;
    return _quiet(
      () async => _folderOf(
        await _channel.invokeMapMethod<String, String>('describeFolder', {
          'uri': uri,
        }),
      ),
      null,
    );
  }

  /// Copies [file] into the folder [folderUri] as [relativeName]
  /// (`Show/Season 01/Show S01E01.mkv`, folders made as needed), deletes
  /// [file], and answers the new file's URI. A name already taken gets
  /// ` (1)` from the system. Throws [PlatformException] when it cannot.
  Future<String> saveToFolder({
    required String folderUri,
    required File file,
    required String relativeName,
  }) async => (await _channel.invokeMethod<String>('saveToFolder', {
    'uri': folderUri,
    'path': file.path,
    'name': relativeName,
    'mimeType': lookupMimeType(relativeName) ?? 'application/octet-stream',
  }))!;

  /// Whether the file behind [uri] (a picked folder's or MediaStore's) is
  /// still there.
  Future<bool> exists(String uri) async {
    if (!isAndroid) return false;
    return _quiet(
      () async =>
          await _channel.invokeMethod<bool>('exists', {'uri': uri}) ?? false,
      false,
    );
  }

  /// Deletes the file behind [uri]; one already gone is fine. Throws
  /// [PlatformException] when it is there and cannot go.
  Future<void> delete(String uri) async {
    if (!isAndroid) return;
    await _channel.invokeMethod<void>('delete', {'uri': uri});
  }

  /// The path behind [uri] when it can be known (internal storage, an SD
  /// card, MediaStore), for what only takes paths.
  Future<String?> pathOf(String uri) async {
    if (!isAndroid) return null;
    return _quiet(
      () => _channel.invokeMethod<String>('pathOf', {'uri': uri}),
      null,
    );
  }

  /// Free space where pieces are fetched and merged; null off Android.
  Future<int?> freeBytes() async {
    if (!isAndroid) return null;
    return _quiet(() => _channel.invokeMethod<int>('freeBytes'), null);
  }

  /// Whether the battery saver leaves the app alone. True off Android, and
  /// when it cannot be read: nothing to ask then.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isAndroid) return true;
    return _quiet(
      () async =>
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true,
      true,
    );
  }

  /// The system's dialog to let the app off the battery saver — when the
  /// app declares `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — or the battery
  /// settings list. The answer is read again when the app comes back.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroid) return;
    await _quiet(
      () => _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations'),
      null,
    );
  }

  static HaulFolder? _folderOf(Map<String, String>? map) => map == null
      ? null
      : HaulFolder(uri: map['uri']!, name: map['name'] ?? map['uri']!);

  static Future<T> _quiet<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }
}
