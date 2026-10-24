import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

/// The slice of background_downloader the engine uses, behind an interface
/// so tests drive the engine with an in-memory fake.
abstract class TransferClient {
  const TransferClient();

  /// Concurrency, and whether the plugin's own holding queue is used. Set
  /// once, before [start].
  Future<void> configure({
    required int maxConcurrent,
    required bool holdingQueue,
    int? foregroundAboveMb,
  });

  /// Where every update of the engine's tasks goes. Registered before
  /// [start], which replays what arrived while the app was dead.
  void listen({
    required void Function(TaskStatusUpdate update) onStatus,
    required void Function(TaskProgressUpdate update) onProgress,
  });

  Future<void> start();

  /// One result per task; a `false` is a task the plugin refused, which
  /// would never report back.
  Future<List<bool>> enqueueAll(List<DownloadTask> tasks);

  Future<void> cancelTasksWithIds(List<String> taskIds);

  /// Resumes a task the platform paused (a notification button, the
  /// system, or before a kill). `false` when it holds nothing to resume
  /// from — the task is running or queued, or its partial data is gone.
  Future<bool> resume(DownloadTask task) async => false;

  /// The engine's tasks the platform still holds: queued, running, paused
  /// or waiting to retry.
  Future<List<Task>> allTasks();
}

/// background_downloader in its own namespace, so the engine's tasks and
/// updates never mix with the app's own use of the plugin — the app keeps
/// `FileDownloader().updates` to itself.
class PluginTransferClient extends TransferClient {
  PluginTransferClient({this.namespace = 'offline_engine'});

  final String namespace;

  /// Fragments and ranges.
  static const pieceGroup = 'pieces';

  /// Files fetched in one request.
  static const fileGroup = 'files';

  FileDownloader get _downloader => FileDownloader.scoped(namespace);

  @override
  Future<void> configure({
    required int maxConcurrent,
    required bool holdingQueue,
    int? foregroundAboveMb,
  }) async {
    await _downloader.configure(
      globalConfig: [
        if (holdingQueue)
          (Config.holdingQueue, (maxConcurrent, maxConcurrent, null)),
        // A big file's partial data must survive until it is resumed; the
        // cache dir may be purged under it.
        (Config.useCacheDir, Config.never),
        if (foregroundAboveMb != null)
          (Config.runInForegroundIfFileLargerThan, foregroundAboveMb),
      ],
      // The plugin's queue on iOS is slow with thousands of tasks, and what
      // starts from the background is throttled: everything is handed to
      // the system at once instead (see the engine's window).
      iOSConfig: holdingQueue ? null : (Config.holdingQueue, false),
    );
  }

  @override
  void listen({
    required void Function(TaskStatusUpdate update) onStatus,
    required void Function(TaskProgressUpdate update) onProgress,
  }) {
    for (final group in const [pieceGroup, fileGroup]) {
      _downloader.registerCallbacks(
        group: group,
        taskStatusCallback: onStatus,
        taskProgressCallback: onProgress,
      );
    }
  }

  @override
  Future<void> start() => _downloader.start(doTrackTasks: false);

  @override
  Future<List<bool>> enqueueAll(List<DownloadTask> tasks) =>
      _downloader.enqueueAll(tasks);

  @override
  Future<void> cancelTasksWithIds(List<String> taskIds) =>
      _downloader.cancelTasksWithIds(taskIds);

  @override
  Future<bool> resume(DownloadTask task) => _downloader.resume(task);

  @override
  Future<List<Task>> allTasks() => _downloader.allTasks(allGroups: true);

  /// Whether this platform hands everything to the system at once.
  static bool get prefersWholeQueue =>
      defaultTargetPlatform == TargetPlatform.iOS;
}
