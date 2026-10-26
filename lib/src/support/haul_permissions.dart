import 'package:background_downloader/background_downloader.dart';
import 'package:haul/src/android/haul_android.dart';

/// What downloads ask the user for. Asked at the first download rather
/// than at app start: Android lets an app ask twice, and without a reason
/// on screen the answer is no.
abstract final class HaulPermissions {
  /// Before a download: notifications, unless [notifications] is false or
  /// they are allowed already — without them a download runs the same,
  /// only unseen outside the app — and, up to Android 9, writing to the
  /// shared folders a finished file goes to.
  static Future<void> forDownload({bool notifications = true}) async {
    if (notifications) await requestNotifications();
    final permissions = FileDownloader().permissions;
    try {
      if (await permissions.status(PermissionType.androidSharedStorage) !=
          PermissionStatus.granted) {
        await permissions.request(PermissionType.androidSharedStorage);
      }
    } on Object {
      // A plugin a maker left out: the sink falls back to the app's folder.
    }
  }

  /// False too when it cannot be read (a plugin a maker left out).
  static Future<bool> notificationsAllowed() async {
    try {
      return await FileDownloader().permissions.status(
            PermissionType.notifications,
          ) ==
          PermissionStatus.granted;
    } on Object {
      return false;
    }
  }

  /// The system's dialog, when not allowed yet. Answers whether they are
  /// allowed now; when Android no longer asks, it answers false at once
  /// (see [enableNotifications]).
  static Future<bool> requestNotifications() async {
    if (await notificationsAllowed()) return true;
    try {
      return await FileDownloader().permissions.request(
            PermissionType.notifications,
          ) ==
          PermissionStatus.granted;
    } on Object {
      return false;
    }
  }

  /// The system's dialog, or the app's notification settings once Android
  /// no longer shows it. Read [notificationsAllowed] again when the app
  /// comes back.
  static Future<void> enableNotifications({
    HaulAndroid android = HaulAndroid.i,
  }) async {
    if (await requestNotifications()) return;
    await android.openNotificationSettings();
  }
}
