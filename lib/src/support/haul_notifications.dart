import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:haul/src/engine/download_engine.dart';
import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/transfer_client.dart';

/// The notifications' texts, already in the user's language: they are shown
/// outside any widget. [forLocale] has Spanish and English.
@immutable
class HaulNotificationTexts {
  const HaulNotificationTexts({
    this.channel = 'Downloads',
    this.failed = 'The download failed',
  });

  /// Spanish for `es`, English otherwise.
  factory HaulNotificationTexts.forLocale(Locale locale) =>
      locale.languageCode == 'es'
      ? const HaulNotificationTexts(
          channel: 'Descargas',
          failed: 'La descarga falló',
        )
      : const HaulNotificationTexts();

  /// The channel's name in the system's notification settings.
  final String channel;
  final String failed;
}

/// A download's progress in the notification shade, on Android.
///
/// A whole file carries background_downloader's own notification on its
/// task — which is what lets a big one run in the foreground: hand [hooks]
/// to `DownloadEngine(hooks:)`. A download in pieces (HLS, DASH, a file in
/// ranges) carries one of these instead: the plugin's grouped notification
/// starts a WorkManager job per queued task just to update its count, and
/// with hundreds of fragments blocks the main thread. This one follows the
/// engine at the pace of its list, and a failure.
///
/// [icon] is a drawable of the app's (`ic_stat_download`): white on
/// transparent, as Android wants a status bar icon.
class HaulNotifications {
  HaulNotifications({
    required this.icon,
    HaulNotificationTexts? texts,
    this.channelId = 'haul_downloads',
    FlutterLocalNotificationsPlugin? plugin,
  }) : texts =
           texts ??
           HaulNotificationTexts.forLocale(PlatformDispatcher.instance.locale),
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final String icon;

  /// Read at each notification: set it again when the language changes.
  HaulNotificationTexts texts;

  /// haul's own channel, apart from the app's.
  final String channelId;
  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;
  StreamSubscription<List<DownloadRecord>>? _records;
  Map<String, DownloadRecord> _seen = {};

  /// The last one shown of each download: progress comes twice a second,
  /// and Android drops updates past five a second — the failure with them,
  /// at times.
  final Map<String, ({int percent, DateTime at})> _shown = {};

  /// Shown again now and then without a change of percent: otherwise it
  /// would go by [_staleAfter] with the download still running.
  static const _refreshEvery = Duration(seconds: 10);

  /// When the process dies nobody updates it: it goes on its own instead of
  /// staying frozen. Each update starts the count again.
  static const _staleAfter = Duration(seconds: 30);

  /// For `DownloadEngine(hooks:)`.
  EngineHooks get hooks => EngineHooks(onWholeFileTask: wholeFileTask);

  /// Dresses a whole file's task with the plugin's notification; for an
  /// app with hooks of its own.
  DownloadTask wholeFileTask(DownloadTask task, DownloadRecord record) {
    FileDownloader.scoped(
      PluginTransferClient().namespace,
    ).configureNotificationForTask(
      task,
      running: TaskNotification(record.title, '{progress} · {networkSpeed}'),
      error: TaskNotification(record.title, texts.failed),
      progressBar: true,
    );
    return task;
  }

  /// Follows [engine] from now on, once it was initialised. What was there
  /// before is not a change: a failure of the last run is not notified
  /// again at each start.
  Future<void> follow(DownloadEngine engine) async {
    _ready =
        await _plugin.initialize(
          settings: InitializationSettings(
            android: AndroidInitializationSettings(icon),
          ),
        ) ??
        false;
    await _records?.cancel();
    _seen = {for (final r in engine.records) r.id: r};
    _records = engine.watchAll().listen(_onRecords);
  }

  Future<void> dispose() async {
    await _records?.cancel();
    _records = null;
  }

  void _onRecords(List<DownloadRecord> records) {
    final seen = {for (final r in records) r.id: r};
    for (final record in records) {
      final before = _seen[record.id];
      if (before != record) unawaited(_notify(before, record));
    }
    for (final id in _seen.keys) {
      if (!seen.containsKey(id)) unawaited(_cancel(id));
    }
    _seen = seen;
  }

  Future<void> _notify(DownloadRecord? before, DownloadRecord record) async {
    // One piece: the plugin's own, on its task.
    if (record.progress.totalPieces <= 1) return;
    switch (record.status) {
      case DownloadStatus.downloading:
        await _progress(record);
      case DownloadStatus.failed when before?.status != DownloadStatus.failed:
        await _failed(record);
      case DownloadStatus.failed:
        break;
      case _ when before?.status == DownloadStatus.downloading:
        await _cancel(record.id);
      case _:
        break;
    }
  }

  /// Away from background_downloader's (the hash of a task id).
  static int _idOf(String downloadId) =>
      0x5D0000 + (downloadId.hashCode & 0xFFFF);

  Future<void> _progress(DownloadRecord record) async {
    if (!_ready) return;
    final percent = ((record.progress.fraction ?? 0) * 100).floor().clamp(
      0,
      100,
    );
    final now = DateTime.now();
    if (_shown[record.id] case final last?
        when last.percent == percent &&
            now.difference(last.at) < _refreshEvery) {
      return;
    }
    _shown[record.id] = (percent: percent, at: now);
    await _plugin.show(
      id: _idOf(record.id),
      title: record.title,
      body: '$percent%',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          texts.channel,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          timeoutAfter: _staleAfter.inMilliseconds,
          category: AndroidNotificationCategory.progress,
        ),
      ),
    );
  }

  Future<void> _failed(DownloadRecord record) async {
    if (!_ready) return;
    // Another notification, not an update of the progress one: those are
    // the ones Android may drop.
    await _cancel(record.id);
    await _plugin.show(
      id: _idOf(record.id),
      title: record.title,
      body: texts.failed,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          texts.channel,
          importance: Importance.low,
          priority: Priority.low,
          category: AndroidNotificationCategory.error,
        ),
      ),
    );
  }

  Future<void> _cancel(String id) async {
    _shown.remove(id);
    if (!_ready) return;
    await _plugin.cancel(id: _idOf(id));
  }
}
