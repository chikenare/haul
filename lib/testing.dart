/// Fakes for testing the engine, and apps built on it, without platform
/// channels, network or ffmpeg.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:offline_engine/src/engine/extension_points.dart';
import 'package:offline_engine/src/engine/transfer_client.dart';
import 'package:offline_engine/src/planner/errors.dart';
import 'package:offline_engine/src/planner/sources/source_fetcher.dart';
import 'package:path/path.dart' as p;

/// In-memory stand-in for background_downloader. Remembers what was
/// enqueued and cancelled; [alive] plays tasks the platform still holds;
/// [complete] writes a piece's file where the plugin would and reports it.
class FakeTransferClient extends TransferClient {
  FakeTransferClient({required this.appSupport});

  /// Where `BaseDirectory.applicationSupport` points.
  final Directory appSupport;

  void Function(TaskStatusUpdate update)? _onStatus;
  void Function(TaskProgressUpdate update)? _onProgress;

  /// Every task handed over, in order.
  final enqueued = <DownloadTask>[];
  final canceledIds = <String>[];

  /// What [allTasks] answers besides what is in flight: tasks that outlived
  /// a kill.
  final alive = <Task>[];

  /// Enqueued, not finished and not cancelled.
  final inFlight = <String, DownloadTask>{};

  int? maxConcurrent;
  bool? holdingQueue;

  /// When set, the next [enqueueAll] answers `false` for every task.
  bool refuseNext = false;

  /// When set, the `canceled` updates of [cancelTasksWithIds] wait in
  /// [heldCancels] until [releaseCancels]: the plugin reports them later,
  /// not inside the call, and the engine may have moved on by then.
  bool holdCancels = false;
  final heldCancels = <TaskStatusUpdate>[];

  void releaseCancels() {
    final held = [...heldCancels];
    heldCancels.clear();
    held.forEach(emit);
  }

  File fileOf(DownloadTask task) =>
      File(p.join(appSupport.path, task.directory, task.filename));

  void emit(TaskStatusUpdate update) => _onStatus?.call(update);

  void emitProgress(TaskProgressUpdate update) => _onProgress?.call(update);

  /// Writes [task]'s file and reports it complete. With a `Range` header
  /// the file gets the range's size unless [bytes] says otherwise.
  Future<void> complete(DownloadTask task, {int? bytes}) async {
    final file = fileOf(task);
    await file.parent.create(recursive: true);
    // Bytes, not a `List<int>`: a 16 MB range as a list of ints is 128 MB.
    await file.writeAsBytes(Uint8List(bytes ?? _rangeSize(task) ?? 10));
    inFlight.remove(task.taskId);
    emit(TaskStatusUpdate(task, TaskStatus.complete));
  }

  /// Completes everything in flight, in order, including what gets
  /// enqueued meanwhile: it only returns once nothing new has come for
  /// [idle]. The engine refills its window after reading the finished
  /// piece from disk, which takes longer than a microtask.
  Future<void> completeAll({
    Duration idle = const Duration(milliseconds: 50),
  }) async {
    var quietSince = DateTime.now();
    while (true) {
      if (inFlight.isNotEmpty) {
        await complete(inFlight.values.first);
        quietSince = DateTime.now();
      } else if (DateTime.now().difference(quietSince) >= idle) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void fail(DownloadTask task, {int? httpStatus, String? description}) {
    inFlight.remove(task.taskId);
    emit(
      TaskStatusUpdate(
        task,
        TaskStatus.failed,
        httpStatus != null
            ? TaskHttpException(description ?? 'HTTP $httpStatus', httpStatus)
            : description == null
            ? null
            : TaskException(description),
      ),
    );
  }

  static int? _rangeSize(DownloadTask task) {
    final range = task.headers['Range'];
    final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range ?? '');
    if (match == null) return null;
    return int.parse(match.group(2)!) - int.parse(match.group(1)!) + 1;
  }

  @override
  Future<void> configure({
    required int maxConcurrent,
    required bool holdingQueue,
    int? foregroundAboveMb,
  }) async {
    this.maxConcurrent = maxConcurrent;
    this.holdingQueue = holdingQueue;
  }

  @override
  void listen({
    required void Function(TaskStatusUpdate update) onStatus,
    required void Function(TaskProgressUpdate update) onProgress,
  }) {
    _onStatus = onStatus;
    _onProgress = onProgress;
  }

  @override
  Future<void> start() async {}

  @override
  Future<List<bool>> enqueueAll(List<DownloadTask> tasks) async {
    if (refuseNext) {
      refuseNext = false;
      return [for (final _ in tasks) false];
    }
    enqueued.addAll(tasks);
    for (final task in tasks) {
      inFlight[task.taskId] = task;
    }
    return [for (final _ in tasks) true];
  }

  @override
  Future<void> cancelTasksWithIds(List<String> taskIds) async {
    canceledIds.addAll(taskIds);
    for (final id in taskIds) {
      final task = inFlight.remove(id);
      alive.removeWhere((t) => t.taskId == id);
      if (task == null) continue;
      final update = TaskStatusUpdate(task, TaskStatus.canceled);
      holdCancels ? heldCancels.add(update) : emit(update);
    }
  }

  @override
  Future<List<Task>> allTasks() async => [...alive, ...inFlight.values];
}

/// Serves fixed responses by URL; anything else is a 404.
class FakeFetcher extends SourceFetcher {
  FakeFetcher(this.responses);

  /// URL (without query) → response builder, given the full URL.
  final Map<String, FetchedResponse Function(Uri url)> responses;

  final requested = <Uri>[];

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    requested.add(url);
    final build =
        responses[url.replace(query: '').toString().replaceAll('?', '')];
    if (build == null) {
      throw SourceException(SourceErrorCode.http(404), '$url');
    }
    return build(url);
  }
}

/// Writes a small file where ffmpeg would; [error] plays a failed merge.
class FakeFfmpeg implements FfmpegRunner {
  FakeFfmpeg({this.error});

  final Object? error;
  final runs = <List<String>>[];

  @override
  Future<void> run(List<String> args) async {
    runs.add(args);
    final error = this.error;
    if (error != null) throw error;
    final output = File(args.last);
    await output.parent.create(recursive: true);
    await output.writeAsString('mkv');
  }
}

/// Collects what the engine reports.
class RecordingLogger implements EngineLogger {
  final warnings = <String>[];
  final errors = <Object>[];

  @override
  void warn(String message) => warnings.add(message);

  @override
  void error(
    Object error,
    StackTrace? stackTrace, {
    Map<String, Object?>? context,
  }) => errors.add(error);
}
