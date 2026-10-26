import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// haul's own Android side (`HaulPlugin.kt`): finished files behind
/// `content://` URIs (MediaStore rows of the public Downloads) and the free
/// space. Off Android every call answers what "nothing to do" means, so
/// callers need no checks.
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

  /// Whether the file behind [uri] is still there.
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
