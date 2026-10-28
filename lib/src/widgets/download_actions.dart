import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/download_engine.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/haul_strings.dart';

/// What can be done with a download.
enum HaulAction {
  pause,
  resume,
  retry,
  play,

  /// Turn a finished package into one file (`DownloadEngine.export`).
  export,

  /// Off the list, its file kept where the user has it.
  removeKeepFile,
  delete,
}

/// The actions [record] allows, decided once for every widget — or for an
/// app drawing its own. [primary] is the one at hand, for an app that puts
/// it on its own button; [menu] all of them, in menu order.
@immutable
class DownloadActions {
  const DownloadActions._(this.primary, this.menu);

  /// [canRetry]: whether a failed one is worth retrying (see
  /// `HaulController.canRetry`); without it, it has no primary action.
  factory DownloadActions.of(
    DownloadRecord record, {
    bool Function(DownloadError error)? canRetry,
  }) {
    final retryable = switch (record.error) {
      final error? => canRetry?.call(error) ?? true,
      null => true,
    };
    final published = isPublished(record);
    final primary = switch (record.status) {
      DownloadStatus.queued ||
      DownloadStatus.resolving ||
      DownloadStatus.downloading => HaulAction.pause,
      DownloadStatus.paused => HaulAction.resume,
      DownloadStatus.failed => retryable ? HaulAction.retry : null,
      DownloadStatus.done => HaulAction.play,
      DownloadStatus.assembling => null,
    };
    return DownloadActions._(primary, [
      ?primary,
      if (record.status == DownloadStatus.done &&
          record.outputKind == OutputKind.package)
        HaulAction.export,
      if (published) HaulAction.removeKeepFile,
      HaulAction.delete,
    ]);
  }

  /// Null while there is nothing to do but wait (finishing, or a failure a
  /// retry would not change).
  final HaulAction? primary;
  final List<HaulAction> menu;

  /// Finished as a file outside the download's folder: deleting the
  /// download may keep it.
  static bool isPublished(DownloadRecord record) {
    final locator = record.outputLocator;
    return record.status == DownloadStatus.done &&
        record.outputKind == OutputKind.file &&
        locator != null &&
        !locator.startsWith('work:');
  }
}

/// Does [action] on [record]. [play] is the app's: haul does not know its
/// player. Deleting asks nothing here; the widgets confirm first. Answers
/// why an export did not happen, or null.
Future<DownloadError?> runHaulAction(
  DownloadEngine engine,
  DownloadRecord record,
  HaulAction action, {
  void Function(DownloadRecord record)? play,
}) async {
  switch (action) {
    case HaulAction.pause:
      await engine.pause(record.id);
    case HaulAction.resume:
      await engine.resume(record.id);
    case HaulAction.retry:
      await engine.retry(record.id);
    case HaulAction.play:
      play?.call(record);
    case HaulAction.export:
      return engine.export(record.id);
    case HaulAction.removeKeepFile:
      await engine.delete(record.id, keepOutput: true);
    case HaulAction.delete:
      await engine.delete(record.id);
  }
  return null;
}

/// What a row says under its title: how much it has (`1.2 GB / 3.0 GB`),
/// its size once done, why it failed, or the state while there are no bytes
/// to show (queued or waiting for Wi-Fi, preparing, finishing). A paused one
/// says so before its bytes, since nothing else on the row does.
String downloadSummary(
  DownloadRecord record,
  HaulStrings strings, {
  bool waitingForWifi = false,
}) {
  final progress = record.progress;
  // A fragmented source's total too: the engine projects it from the
  // pieces already in, so it settles on the real size as it goes.
  final bytes = progress.bytes > 0
      ? progress.totalBytes > 0
            ? '${strings.bytes(progress.bytes)} / '
                  '${strings.bytes(progress.totalBytes)}'
            : strings.bytes(progress.bytes)
      : null;
  return switch (record.status) {
    DownloadStatus.failed => switch (record.error) {
      final error? => strings.error(error),
      null => strings.status(record.status),
    },
    DownloadStatus.queued when waitingForWifi => strings.waitingForWifi,
    DownloadStatus.done =>
      progress.totalBytes > 0 ? strings.bytes(progress.totalBytes) : '',
    DownloadStatus.downloading => bytes ?? '',
    DownloadStatus.paused => [
      strings.status(record.status),
      ?bytes,
    ].join(' · '),
    DownloadStatus.queued ||
    DownloadStatus.resolving ||
    DownloadStatus.assembling => strings.status(record.status),
  };
}
