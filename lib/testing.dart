/// Fakes for testing the engine, and apps built on it, without platform
/// channels, network or ffmpeg.
library;

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/transfer_client.dart';
import 'package:haul/src/planner/errors.dart';
import 'package:haul/src/planner/sources/source_fetcher.dart';
import 'package:path/path.dart' as p;

/// In-memory stand-in for background_downloader, as it behaves: a
/// cancelled task is still listed by [allTasks] until its `canceled` update
/// is delivered; a paused one is listed too, and only [resume] brings it
/// back; a refused enqueue leaves nothing behind. Remembers what was
/// enqueued and cancelled; [alive] plays tasks that outlived a kill;
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
  final resumed = <String>[];

  /// What [allTasks] answers besides the rest: tasks that outlived a kill.
  final alive = <Task>[];

  /// Enqueued, not finished, not cancelled and not paused.
  final inFlight = <String, DownloadTask>{};

  /// Paused by the plugin (a notification button, the system): listed, and
  /// waiting for [resume].
  final paused = <String, DownloadTask>{};

  /// Cancelled, with the `canceled` update not delivered yet: still listed.
  final cancelling = <String, Task>{};

  int? maxConcurrent;
  bool? holdingQueue;

  /// When set, the next [enqueueAll] answers `false` for every task.
  bool refuseNext = false;

  /// When set, [resume] answers `false`: no resume data was kept.
  bool refuseResume = false;

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

  /// Delivers [update]. A final one takes the task off every list, as the
  /// plugin forgets a task once it has reported how it ended.
  void emit(TaskStatusUpdate update) {
    if (update.status.isFinalState) _forget(update.task.taskId);
    _onStatus?.call(update);
  }

  void _forget(String taskId) {
    inFlight.remove(taskId);
    paused.remove(taskId);
    cancelling.remove(taskId);
    alive.removeWhere((t) => t.taskId == taskId);
  }

  void emitProgress(TaskProgressUpdate update) => _onProgress?.call(update);

  /// Writes [task]'s file and reports it complete. With a `Range` header
  /// the file gets the range's size unless [bytes] says otherwise.
  Future<void> complete(DownloadTask task, {int? bytes}) async {
    final file = fileOf(task);
    await file.parent.create(recursive: true);
    // Bytes, not a `List<int>`: a 16 MB range as a list of ints is 128 MB.
    await file.writeAsBytes(Uint8List(bytes ?? _rangeSize(task) ?? 10));
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

  /// What the plugin does when a notification button or the system pauses
  /// a task: it waits, listed, for [resume].
  void pauseByPlatform(DownloadTask task) {
    inFlight.remove(task.taskId);
    paused[task.taskId] = task;
    emit(TaskStatusUpdate(task, TaskStatus.paused));
  }

  /// What Android does a moment after pausing a task at the background time
  /// limit: it runs it again by itself, without [resume].
  void rerunByPlatform(DownloadTask task) {
    paused.remove(task.taskId);
    inFlight[task.taskId] = task;
    emit(TaskStatusUpdate(task, TaskStatus.running));
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
      final task =
          inFlight.remove(id) ??
          paused.remove(id) ??
          alive.where((t) => t.taskId == id).firstOrNull;
      alive.removeWhere((t) => t.taskId == id);
      if (task == null) continue;
      cancelling[id] = task;
      final update = TaskStatusUpdate(task, TaskStatus.canceled);
      holdCancels ? heldCancels.add(update) : emit(update);
    }
  }

  @override
  Future<bool> resume(DownloadTask task) async {
    final held = paused[task.taskId];
    if (held == null || refuseResume) return false;
    paused.remove(task.taskId);
    inFlight[task.taskId] = held;
    resumed.add(task.taskId);
    emit(TaskStatusUpdate(held, TaskStatus.running));
    return true;
  }

  @override
  Future<List<Task>> allTasks() async => [
    ...alive,
    ...inFlight.values,
    ...paused.values,
    ...cancelling.values,
  ];
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

/// Wi-Fi as a test sets it: [set] changes what [onWifi] answers, and tells
/// whoever listens — or, with `announce: false`, not yet (the platform
/// noticing before the app's connectivity package does).
class FakeWifiMonitor implements WifiMonitor {
  FakeWifiMonitor({bool onWifi = true}) : _onWifi = onWifi;

  bool _onWifi;
  final _changes = StreamController<bool>.broadcast();

  void set(bool onWifi, {bool announce = true}) {
    _onWifi = onWifi;
    if (announce) _changes.add(onWifi);
  }

  @override
  Future<bool> onWifi() async => _onWifi;

  @override
  Stream<bool> get changes => _changes.stream;
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

/// Android's side as a test sets it: folders that can or cannot be
/// written, files that exist, the battery saver's answer.
class FakeHaulAndroid implements HaulAndroid {
  FakeHaulAndroid({this.isAndroid = true, this.batteryFree = false});

  @override
  final bool isAndroid;

  bool batteryFree;
  int batteryRequests = 0;

  /// What [pickFolder] answers next.
  HaulFolder? picked;

  /// Folders [saveToFolder] can no longer write to.
  final revoked = <String>{};

  /// `(folderUri, relativeName)` of every save.
  final saved = <(String, String)>[];
  final deleted = <String>[];

  /// URIs that [exists] answers true for; saves add theirs.
  final existing = <String>{};

  @override
  Future<HaulFolder?> pickFolder({String? initialUri}) async => picked;

  @override
  Future<HaulFolder?> describeFolder(String uri) async => revoked.contains(uri)
      ? null
      : HaulFolder(uri: uri, name: Uri.decodeComponent(uri.split('/').last));

  @override
  Future<String> saveToFolder({
    required String folderUri,
    required File file,
    required String relativeName,
  }) async {
    if (revoked.contains(folderUri)) {
      throw PlatformException(code: 'io', message: 'no grant');
    }
    saved.add((folderUri, relativeName));
    await file.delete();
    final uri = '$folderUri/document/${Uri.encodeComponent(relativeName)}';
    existing.add(uri);
    return uri;
  }

  @override
  Future<bool> exists(String uri) async => existing.contains(uri);

  @override
  Future<void> delete(String uri) async {
    deleted.add(uri);
    existing.remove(uri);
  }

  @override
  Future<String?> pathOf(String uri) async => null;

  @override
  Future<int?> freeBytes() async => null;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryFree;

  @override
  Future<void> requestIgnoreBatteryOptimizations() async {
    batteryRequests++;
  }
}
