import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/errors.dart';
import 'package:haul/src/engine/extension_points.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/output_sinks.dart';
import 'package:haul/src/engine/record_store.dart';
import 'package:haul/src/engine/transfer_client.dart';
import 'package:haul/src/planner/assembly/local_packager.dart';
import 'package:haul/src/planner/assembly/mkv_args.dart';
import 'package:haul/src/planner/assembly/mux_input.dart';
import 'package:haul/src/planner/assembly/track_assembler.dart';
import 'package:haul/src/planner/errors.dart';
import 'package:haul/src/planner/media_options.dart';
import 'package:haul/src/planner/plan.dart';
import 'package:haul/src/planner/sources/resolved_source.dart';
import 'package:haul/src/planner/sources/source_resolver.dart';
import 'package:haul/src/planner/track_criteria.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tuning, with defaults that suit every platform.
class EngineConfig {
  const EngineConfig({
    this.rootFolder = 'haul',
    this.maxConcurrent = 8,
    this.window,
    this.retries = 3,
    this.progressInterval = const Duration(milliseconds: 500),
    this.linkMargin = const Duration(minutes: 30),
    this.foregroundAboveMb,
    this.refreshTimeout = const Duration(minutes: 1),
    this.platformPauseGrace = const Duration(seconds: 2),
  });

  /// Inside application support: one folder per download.
  final String rootFolder;

  /// Pieces at once.
  final int maxConcurrent;

  /// How many pieces are handed to the downloader at a time, refilled as
  /// they finish; null hands over everything left. Null by default on iOS,
  /// where the system schedules best what it gets while the app is in
  /// front, and 4× [maxConcurrent] elsewhere: thousands of tasks queued at
  /// once are slow to keep on Android and lost with the queue on a kill.
  final int? window;

  /// The downloader's own retries per piece, before the download fails.
  final int retries;

  /// At most one progress emission per download per interval.
  final Duration progressInterval;

  /// A link closer than this to expiring is refreshed before starting: the
  /// download has to finish inside it.
  final Duration linkMargin;

  /// On Android, whole files bigger than this run in the foreground, which
  /// needs a notification on their task (see `EngineHooks.onWholeFileTask`).
  final int? foregroundAboveMb;

  /// How long the app's `SourceRefresher` may take before the download
  /// fails as a network error.
  final Duration refreshTimeout;

  /// How long a whole file paused by the platform may take to start again
  /// on its own before the pause counts as the user's. Android pauses one
  /// that hits the background time limit and runs it again a second later;
  /// a notification's pause button looks the same, and stays.
  final Duration platformPauseGrace;
}

/// Offline downloads end to end: reads each title's source, picks its
/// tracks, fetches every piece through background_downloader, and leaves a
/// local HLS package or one file.
///
/// Titles go through the queue one at a time; within one, pieces run in
/// parallel. What is fetched is what the disk holds — a piece is done once
/// its file exists with the right size — so starting, resuming, retrying
/// and picking up after a kill are the same thing: asking for what is
/// missing. A pause cancels the pieces in flight and keeps the rest; big
/// files come in byte ranges, so that holds for them too.
class DownloadEngine {
  DownloadEngine({
    this.config = const EngineConfig(),
    SourceRefresher? refresher,
    CriteriaProvider? criteria,
    OutputSink sink = const PrivateSink(),
    FfmpegRunner? ffmpeg,
    EngineHooks hooks = const EngineHooks(),
    ValueListenable<bool>? wifiOnly,
    WifiMonitor? wifi,
    EngineLogger logger = const PrintLogger(),
    TransferClient? transfer,
    SourceResolver resolver = const SourceResolver(),
    RecordStore? store,
    Future<Directory> Function()? appSupport,
  }) : _refresher = refresher,
       _criteria = criteria,
       _sink = sink,
       _ffmpeg = ffmpeg,
       _hooks = hooks,
       _wifiOnly = wifiOnly,
       _wifi = wifi,
       _logger = logger,
       _transfer = transfer ?? PluginTransferClient(),
       _resolver = resolver,
       _appSupport = appSupport ?? getApplicationSupportDirectory,
       _storeOverride = store;

  final EngineConfig config;
  final SourceRefresher? _refresher;
  final CriteriaProvider? _criteria;
  final OutputSink _sink;
  final FfmpegRunner? _ffmpeg;
  final EngineHooks _hooks;

  /// The user's "only on Wi-Fi", read when each piece is handed over and
  /// followed while it changes. Null: never.
  final ValueListenable<bool>? _wifiOnly;

  /// Tells a Wi-Fi drop from a network error, and when to go on. Without
  /// it, a piece the platform held for Wi-Fi until it ran out of retries
  /// fails the download as a network error.
  final WifiMonitor? _wifi;
  final EngineLogger _logger;
  final TransferClient _transfer;
  final SourceResolver _resolver;
  final Future<Directory> Function() _appSupport;
  final RecordStore? _storeOverride;

  /// Not final: a failed init is tried again (see [init]).
  late RecordStore _store;

  static const _packager = LocalPackager();
  static const _assembler = TrackAssembler();
  static const _planFile = 'plan.json';
  static const _master = 'master.m3u8';
  static const _subtitlesFile = 'subtitles.json';
  static const _subsDir = 'subs';

  /// Prefix of a locator inside the download's own folder: stored relative,
  /// because the container path changes on iOS between installs.
  static const _workPrefix = 'work:';

  late Directory _root;
  final Map<String, DownloadRecord> _records = {};
  final Map<String, _Job> _jobs = {};

  /// Records that were active when the engine started: their tasks of the
  /// record's last run may still be running in the platform, and their
  /// first start here follows them instead of asking for them again.
  final Set<String> _recovering = {};

  /// Pieces of a record's current run reported complete while it had no
  /// job yet (between a kill and its start): counted when the job is made,
  /// without trusting the file's mere existence (see [_copiesInPlace]).
  final Set<String> _completedEarly = {};

  /// Clean-up after a failure (cancelling the rest, wiping pieces) still
  /// running per download: the next start waits for it, so it never reads
  /// a folder being emptied.
  final Map<String, Future<void>> _cleanups = {};

  /// Whole files the platform paused, waiting [EngineConfig.platformPauseGrace]
  /// to see whether it runs them again: task id → its timer.
  final Map<String, Timer> _platformPauses = {};

  /// The last thing [_wifi] said; on Wi-Fi until it says otherwise.
  bool _onWifi = true;
  StreamSubscription<bool>? _wifiChanges;

  final _changes = StreamController<void>.broadcast(sync: true);
  Future<void>? _ready;
  bool _pumping = false;
  bool _pumpAgain = false;
  bool _disposed = false;

  int get _window =>
      config.window ??
      (PluginTransferClient.prefersWholeQueue
          ? 1 << 30
          : config.maxConcurrent * 4);

  /// Whether the downloader moves a finished file into place in one step,
  /// so a file there is a finished one. On desktop it may copy it instead,
  /// and a copy cut short looks like a file too.
  static bool get _copiesInPlace => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => false,
    _ => true,
  };

  // ---------------------------------------------------------------------
  // Life

  /// Idempotent. Loads the records, picks up what a kill left behind and
  /// starts the queue — so call it at app start, not when a screen opens.
  /// A failed init (an unreadable folder, a plugin that would not start) is
  /// not kept: the next call tries again.
  Future<void> init() => _ready ??= _init().catchError((Object e) {
    _ready = null;
    throw e;
  });

  Future<void> _init() async {
    _root = Directory(p.join((await _appSupport()).path, config.rootFolder));
    _store = _storeOverride ?? JsonRecordStore(() async => _root);

    _records.clear();
    for (final record in await _store.loadAll()) {
      _records[record.id] = record;
    }

    await _transfer.configure(
      maxConcurrent: config.maxConcurrent,
      holdingQueue: !PluginTransferClient.prefersWholeQueue,
      foregroundAboveMb: config.foregroundAboveMb,
    );
    // Before start(), which replays what arrived while the app was dead.
    _transfer.listen(
      onStatus: (update) => unawaited(
        _onStatus(
          update,
        ).catchError((Object e, StackTrace st) => _logger.error(e, st)),
      ),
      onProgress: _onProgress,
    );
    await _transfer.start();

    for (final record in _records.values.toList()) {
      if (record.isActive) {
        _recovering.add(record.id);
        _put(record.copyWith(status: DownloadStatus.queued));
      }
    }
    await _cancelStrayTasks();

    // A failed init comes through here again: one subscription, not two.
    final wifi = _wifi;
    if (wifi != null) {
      await _wifiChanges?.cancel();
      _onWifi = await wifi.onWifi();
      _wifiChanges = wifi.changes.listen(_setOnWifi);
    }
    _wifiOnly?.removeListener(_onWifiOnlyChanged);
    _wifiOnly?.addListener(_onWifiOnlyChanged);

    _emit();
    unawaited(_pump());
  }

  /// Starts the engine if the app has not: every public call works on a
  /// loaded engine.
  Future<void> _whenReady() async {
    try {
      await init();
    } on Object {
      // Reported by whoever started init.
    }
  }

  /// Stops reporting and acting: work in progress (a source being read, a
  /// batch being enqueued) goes no further and writes no record, so it
  /// cannot race the next engine on the same folder. Tasks keep running in
  /// the platform; the next engine picks them up.
  Future<void> dispose() async {
    _disposed = true;
    _jobs.clear();
    for (final timer in _platformPauses.values) {
      timer.cancel();
    }
    _platformPauses.clear();
    _wifiOnly?.removeListener(_onWifiOnlyChanged);
    await _wifiChanges?.cancel();
    await _changes.close();
  }

  // ---------------------------------------------------------------------
  // Reading

  /// Newest first.
  List<DownloadRecord> get records =>
      _records.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  DownloadRecord? byId(String id) => _records[id];

  /// Only on Wi-Fi and not on it: nothing starts, and what was downloading
  /// is back in the queue until Wi-Fi returns. A queued record is waiting
  /// for Wi-Fi rather than for its turn. [watchAll] emits when it changes.
  bool get waitingForWifi => _requiresWifi && !_onWifi;

  bool get _requiresWifi => _wifiOnly?.value ?? false;

  DownloadRecord? byKey(String key) =>
      _records.values.where((r) => r.key == key).firstOrNull;

  /// [records] now and after every change. The changes are followed before
  /// the first snapshot is taken, in the same step: a change made while it
  /// is being handed over comes after it instead of being lost.
  Stream<List<DownloadRecord>> watchAll() => Stream.multi((controller) {
    StreamSubscription<void>? changes;
    var cancelled = false;
    controller.onCancel = () {
      cancelled = true;
      return changes?.cancel();
    };
    unawaited(
      _whenReady().then((_) {
        if (cancelled) return;
        changes = _changes.stream.listen(
          (_) => controller.add(records),
          onDone: controller.close,
        );
        controller.add(records);
      }),
    );
  });

  /// One record now and after every change, until it is deleted (null).
  Stream<DownloadRecord?> watch(String id) =>
      watchAll().map((_) => _records[id]).distinct();

  /// Where a finished download is on disk: its master playlist or its file.
  /// Null before it is done, or when the sink's locator is not a path.
  String? outputPath(DownloadRecord record) {
    final locator = record.outputLocator;
    if (locator == null) return null;
    if (locator.startsWith(_workPrefix)) {
      return p.join(
        _workDir(record.id).path,
        locator.substring(_workPrefix.length),
      );
    }
    return p.isAbsolute(locator) ? locator : null;
  }

  /// The subtitles a finished download keeps as files — the package's, or
  /// the sidecars beside a merged file — only the ones still on disk.
  Future<List<PackagedSubtitle>> subtitlesOf(String id) async {
    if (!_records.containsKey(id)) return const [];
    final subtitles = await LocalPackager.subtitlesOf(
      p.join(_workDir(id).path, _master),
    );
    return [
      for (final s in subtitles)
        if (await File(s.path).exists()) s,
    ];
  }

  // ---------------------------------------------------------------------
  // Asking

  /// Puts [request] in the queue. A key already offline or on its way stays
  /// as it is; one that failed starts again with the new source, keeping
  /// the pieces on disk when they still line up.
  Future<EnqueueResult> enqueue(DownloadRequest request) {
    final result = _enqueuing.then((_) => _enqueue(request));
    _enqueuing = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Enqueues run one after another: one with a ready plan writes it before
  /// its record exists, and a second for the same key meanwhile would not
  /// find the first and make another record.
  Future<void> _enqueuing = Future.value();

  Future<EnqueueResult> _enqueue(DownloadRequest request) async {
    await _whenReady();
    final now = DateTime.now();
    final existing = byKey(request.key);

    if (existing != null && existing.status != DownloadStatus.failed) {
      return (id: existing.id, outcome: EnqueueOutcome.existing);
    }

    final id = existing?.id ?? _newId();
    await _cleanups[id];
    final plan = request.plan;
    var replan = false;
    if (existing != null) {
      final sameSource = existing.source == request.source;
      final sameTracks = existing.tracks == request.tracks;
      final sameOutput = existing.output == request.output;
      // The file merged for the failed attempt is another one now.
      if (!sameOutput || (plan == null && !sameTracks)) {
        await _deleteStaged(id);
      }
      // Planned again at its turn from the new source or choice: the plan
      // on disk would otherwise be used as it is.
      replan = plan == null && !(sameSource && sameTracks && sameOutput);
    }
    if (plan != null) {
      final saved = await _readPlan(id);
      if (saved != null && !saved.linesUpWith(plan)) await _wipePieces(id);
      await _writePlan(id, plan);
    }

    _put(
      (existing ??
              DownloadRecord(
                id: id,
                key: request.key,
                title: request.title,
                name: request.name,
                status: DownloadStatus.queued,
                source: request.source,
                createdAt: now,
                updatedAt: now,
              ))
          .copyWith(
            title: request.title,
            name: request.name,
            metadata: request.metadata,
            status: DownloadStatus.queued,
            error: null,
            source: request.source,
            expiresAt: request.expiresAt,
            // A refused link stays refused until a fresh one comes.
            linkDead:
                existing != null &&
                existing.source == request.source &&
                existing.linkDead,
            replan: replan,
            tracks: request.tracks,
            output: request.output,
            stagedPath: null,
            publishTarget: existing?.output == request.output
                ? existing?.publishTarget
                : null,
            updatedAt: now,
          ),
    );
    unawaited(_pump());
    return (
      id: id,
      outcome: existing == null
          ? EnqueueOutcome.created
          : EnqueueOutcome.replacedFailed,
    );
  }

  Future<List<EnqueueResult>> enqueueAll(
    List<DownloadRequest> requests,
  ) async => [for (final request in requests) await enqueue(request)];

  /// Stops the pieces in flight; what is on disk stays for [resume].
  Future<void> pause(String id) async {
    await _whenReady();
    final paused = _transition(id, const {
      DownloadStatus.queued,
      DownloadStatus.resolving,
      DownloadStatus.downloading,
    }, DownloadStatus.paused);
    if (!paused) return;
    await _stopJob(id);
    // Still running from before a kill, with no job to stop yet.
    if (_recovering.contains(id)) await _cancelTasksOf(id);
    unawaited(_pump());
  }

  /// Back in the queue; what is on disk is not asked for again.
  Future<void> resume(String id) => _requeue(id);

  /// Back in the queue after a failure. A link that ran out or was refused
  /// is refreshed at its turn.
  Future<void> retry(String id) => _requeue(id);

  Future<void> _requeue(String id) async {
    await _whenReady();
    final moved = _transition(
      id,
      const {DownloadStatus.paused, DownloadStatus.failed},
      DownloadStatus.queued,
      also: (r) => r.copyWith(error: null),
    );
    if (moved) unawaited(_pump());
  }

  /// Cancels whatever is in flight and removes the download, its folder and
  /// what it published — unless [keepOutput]: a finished file the user keeps
  /// in their folder, only taken off the list. A package lives in the
  /// download's folder, so it goes either way.
  Future<void> delete(String id, {bool keepOutput = false}) async {
    await _whenReady();
    final record = _records.remove(id);
    if (record == null) return;
    _emit();
    await _stopJob(id);
    await _cancelTasksOf(id);
    _completedEarly.removeWhere((t) => _parseTaskId(t)?.id == id);

    final locator = record.outputLocator;
    if (!keepOutput && locator != null && !locator.startsWith(_workPrefix)) {
      try {
        await _sink.remove(locator);
      } on Object catch (e, st) {
        _logger.error(e, st, context: {'id': id, 'step': 'remove'});
      }
    }
    await _cleanups[id];
    await _store.delete(id);
    await _deleteQuietly(_workDir(id));
    unawaited(_pump());
  }

  /// Deletes everything not finished. Answers how many went. A title that
  /// finished once and is being exported, or failed publishing its export,
  /// is not pending: it stays.
  Future<int> cancelPending() async {
    await _whenReady();
    final pending = [
      for (final r in _records.values)
        if (r.status != DownloadStatus.done && r.outputLocator == null) r.id,
    ];
    for (final id in pending) {
      await delete(id);
    }
    return pending.length;
  }

  /// Replaces the app's data on a record.
  Future<void> updateMetadata(String id, Map<String, Object?> metadata) async {
    await _whenReady();
    final record = _records[id];
    if (record != null) _put(record.copyWith(metadata: metadata));
  }

  /// Turns a finished package into one file, handed to the sink as if it
  /// had been asked for with [OutputMode.file] — under [name], or the
  /// record's. The package goes once the file is written: keeping both
  /// would take the title's space twice.
  ///
  /// Answers null when done, or why not. A failure before the file was
  /// written leaves the package as it was, still done; after it, the
  /// download fails as any publish would, and [retry] only publishes again.
  /// Throws [StateError] when [id] is not a finished package.
  Future<DownloadError?> export(String id, {OutputName? name}) async {
    await _whenReady();
    final before = _records[id];
    final exported = _transition(
      id,
      const {DownloadStatus.done},
      DownloadStatus.assembling,
      also: (r) => r.copyWith(
        output: OutputMode.file,
        name: name ?? r.name,
        error: null,
      ),
      when: (r) => r.outputKind == OutputKind.package,
    );
    if (!exported) throw StateError('$id is not a finished package');

    final plan = await _readPlan(id);
    try {
      if (plan == null) {
        throw const SourceException(SourceErrorCode.missingPieces, 'no plan');
      }
      await _exportFile(_records[id]!, plan);
      return null;
    } catch (e, st) {
      final error = _assemblyError(id, e, st);
      if (plan != null && await _readyToPublish(id)) {
        _fail(id, error);
      } else {
        // Nothing written: the package is still whole, and still plays.
        _transition(
          id,
          const {DownloadStatus.assembling},
          DownloadStatus.done,
          also: (r) => r.copyWith(output: before!.output, name: before.name),
        );
      }
      return error;
    } finally {
      unawaited(_pump());
    }
  }

  // ---------------------------------------------------------------------
  // Wi-Fi

  void _setOnWifi(bool onWifi) {
    if (_disposed || onWifi == _onWifi) return;
    _onWifi = onWifi;
    _emit();
    unawaited(_requeueMoving().whenComplete(_pump));
  }

  /// A piece found Wi-Fi gone before [_wifi] said so — or after, with its
  /// download still moving: either way it goes back to the queue.
  void _holdForWifi() {
    if (_disposed) return;
    _onWifi = false;
    _emit();
    unawaited(_requeueMoving().whenComplete(_pump));
  }

  /// The pieces in flight were handed over with the old requirement: they
  /// are asked for again with the new one. What is on disk stays.
  void _onWifiOnlyChanged() {
    if (_disposed) return;
    _emit();
    unawaited(_requeueMoving().whenComplete(_pump));
  }

  /// The download reading its source or fetching goes back to the queue,
  /// its pieces in flight cancelled; [_pump] starts it again when it may.
  Future<void> _requeueMoving() async {
    for (final record in _records.values.toList()) {
      final moved = _transition(record.id, const {
        DownloadStatus.resolving,
        DownloadStatus.downloading,
      }, DownloadStatus.queued);
      if (!moved) continue;
      await _stopJob(record.id);
      if (_recovering.contains(record.id)) await _cancelTasksOf(record.id);
    }
  }

  /// Whether a piece's failure is Wi-Fi going away under a download that
  /// only runs on it, rather than the network failing.
  Future<bool> _lostWifi(TaskStatusUpdate update) async {
    final wifi = _wifi;
    if (wifi == null || !_requiresWifi) return false;
    if (update.exception is TaskHttpException) return false;
    if (isOutOfSpace(update.exception?.description ?? '')) return false;
    return !await wifi.onWifi();
  }

  // ---------------------------------------------------------------------
  // Queue

  /// One download at a time. Calls that arrive while it runs fold into it.
  Future<void> _pump() async {
    if (_disposed) return;
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        while (!_records.values.any((r) => r.isActive)) {
          // Reading a source goes over the network too, not only pieces.
          if (waitingForWifi) break;
          final next = _next();
          if (next == null) break;
          await _startSafely(next.id);
        }
      } while (_pumpAgain);
    } catch (e, st) {
      _logger.error(e, st);
    } finally {
      _pumping = false;
    }
  }

  /// The oldest queued download — but one that was running before a kill
  /// first: its pieces are still running in the platform.
  DownloadRecord? _next() {
    final queued = _records.values
        .where((r) => r.status == DownloadStatus.queued)
        .toList();
    if (queued.isEmpty) return null;
    queued.sort((a, b) {
      final byRecovery = (_recovering.contains(a.id) ? 0 : 1).compareTo(
        _recovering.contains(b.id) ? 0 : 1,
      );
      return byRecovery != 0 ? byRecovery : a.createdAt.compareTo(b.createdAt);
    });
    return queued.first;
  }

  /// [_start] without leaving the record active when something throws: the
  /// queue would stall for good.
  Future<void> _startSafely(String id) async {
    try {
      await _start(id);
    } catch (e, st) {
      await _stopJob(id);
      // Paused or deleted while the source was read: that answer stands.
      final status = _records[id]?.status;
      if (status != DownloadStatus.resolving &&
          status != DownloadStatus.downloading) {
        return;
      }
      final error = switch (e) {
        RefreshException(:final code, :final message) => DownloadError(
          code: code,
          message: message,
        ),
        _ => downloadErrorOf(e),
      };
      if (error.code == DownloadErrorCode.unknown) {
        _logger.error(e, st, context: {'id': id, 'step': 'start'});
      }
      _fail(id, error);
    }
  }

  /// Plans the download if it has no plan yet, then asks the downloader for
  /// the pieces missing on disk.
  Future<void> _start(String id) async {
    if (!_transition(id, const {
      DownloadStatus.queued,
    }, DownloadStatus.resolving)) {
      return;
    }
    await _cleanups[id];

    // A file merged and not handed to the sink yet — a failed publish, or
    // a kill in between — only needs publishing: its pieces went when it
    // was written, so planning would fetch them all again.
    if (await _readyToPublish(id)) {
      _recovering.remove(id);
      if (_transition(id, const {
        DownloadStatus.resolving,
      }, DownloadStatus.downloading)) {
        await _assemble(id);
      }
      return;
    }

    final plan = await _planFor(id);
    if (plan == null || _records[id]?.status != DownloadStatus.resolving) {
      return;
    }
    // Only a first start after a kill follows the tasks of the last run;
    // a plan made again cancelled them (see [_planFor]).
    final adopt = _recovering.remove(id);

    final missing = <_Piece>[];
    var settledBytes = 0;
    for (final (t, track) in plan.tracks.indexed) {
      // One listing per track, not a lookup per piece: an episode is
      // thousands of fragments.
      final onDisk = await _sizesIn(_trackDir(id, t));
      for (final (i, piece) in track.pieces.indexed) {
        final size = onDisk[piece.file];
        final expected = piece.expectedBytes;
        if (size != null && (expected == null || size == expected)) {
          settledBytes += size;
          continue;
        }
        // Cut short (a range, or a copy interrupted on desktop): asked
        // again.
        if (size != null) {
          await _deleteQuietly(File(p.join(_trackDir(id, t).path, piece.file)));
        }
        missing.add(_Piece(t, i, track, piece));
      }
    }

    var record = _records[id];
    if (record?.status != DownloadStatus.resolving) return;
    // A new run, saved before any of its tasks exists: after a kill, the
    // next engine must know which tasks are this attempt's.
    final run = adopt ? record!.run : record!.run + 1;
    if (run != record.run) {
      _put(record.copyWith(run: run), persist: false);
      await _store.save(_records[id]!);
    }

    final progress = DownloadProgress(
      donePieces: plan.pieceCount - missing.length,
      totalPieces: plan.pieceCount,
      bytes: settledBytes,
      totalBytes: plan.expectedBytes,
      // A file in ranges weighs exactly what its server said: counted by
      // bytes, not in 16 MB steps.
      segmented: plan.tracks.any(
        (t) => t.pieces.length > 1 && t.assembly != TrackAssembly.ranges,
      ),
    );
    final started = _transition(
      id,
      const {DownloadStatus.resolving},
      DownloadStatus.downloading,
      also: (r) => r.copyWith(progress: progress, error: null),
    );
    if (!started) return;

    if (missing.isEmpty) {
      await _assemble(id);
      return;
    }

    // What the platform still holds of this run after a kill is followed,
    // not asked for twice; anything of another run is let go.
    final alive = <String, Task>{};
    final stray = <String>[];
    for (final task in await _transfer.allTasks()) {
      final ids = _parseTaskId(task.taskId);
      if (ids?.id != id) continue;
      if (adopt && ids!.run == run) {
        alive[task.taskId] = task;
      } else {
        stray.add(task.taskId);
      }
    }
    if (_records[id]?.status != DownloadStatus.downloading) return;

    final job = _jobs[id] = _Job(
      id: id,
      run: run,
      plan: plan,
      progress: progress,
      settledBytes: settledBytes,
    );
    for (final piece in missing) {
      final taskId = piece.taskId(id, run);
      job.pieces[taskId] = piece;
      job.pending.add(taskId);
      if (alive.containsKey(taskId)) {
        job.inFlight.add(taskId);
      } else {
        job.queue.add(piece);
      }
    }
    await _transfer.cancelTasksWithIds(stray);
    // A task the platform paused before the kill would wait for good.
    for (final taskId in job.inFlight.toList()) {
      if (alive[taskId] case final DownloadTask task when task.allowPause) {
        await _transfer.resume(task);
      }
    }

    await _feed(job);
    await _settleFinishedPieces(job);
  }

  /// Whether [id] has its one file written — or handed to a sink that
  /// already holds it — and the plan it came from. Read from the disk, not
  /// the record: a kill can fall between writing the file and saving that.
  Future<bool> _readyToPublish(String id) async {
    final plan = await _readPlan(id);
    final record = _records[id];
    if (plan == null || record == null) return false;
    if (await _stagedFile(id, plan).exists()) return true;
    final target = record.publishTarget;
    final sink = _sink;
    return target != null &&
        sink is ReservingOutputSink &&
        await sink.holds(target);
  }

  File _stagedFile(String id, DownloadPlan plan) =>
      File(p.join(_workDir(id).path, 'output.${plan.extension}'));

  /// The plan on disk, or a new one. A plan whose link ran out is planned
  /// again from a fresh link with the same choice; one whose request
  /// changed, from the new request. Either keeps the pieces on disk when
  /// they are the same files, and otherwise starts over.
  ///
  /// Null when the record was paused or deleted meanwhile: nothing is
  /// written then.
  Future<DownloadPlan?> _planFor(String id) async {
    final record = _records[id]!;
    final saved = await _readPlan(id);
    final expired =
        record.linkDead ||
        (record.expiresAt?.isBefore(DateTime.now().add(config.linkMargin)) ??
            false);
    if (saved != null && !expired && !record.replan) return saved;
    // Pieces without a plan (a corrupt range took it): whatever they are,
    // a new plan must not count them as its own.
    if (saved == null) await _wipePieces(id);

    var source = record.source;
    final refresher = _refresher;
    if (expired && refresher != null) {
      // An app's refresher has no timeout of its own, and the queue waits
      // for this title: one that never answers would hold up every other.
      final fresh = await refresher
          .refresh(record)
          .timeout(config.refreshTimeout);
      final current = _records[id];
      if (current == null) return null;
      // Kept even when paused meanwhile: a fresh link may have cost the
      // user an allowance, and the resume would otherwise mint another.
      _put(
        current.copyWith(
          source: fresh.source,
          expiresAt: fresh.expiresAt,
          linkDead: false,
          metadata: fresh.metadata ?? current.metadata,
        ),
      );
      if (current.status != DownloadStatus.resolving) return null;
      source = fresh.source;
    }

    final resolved = await _resolver.resolve(source);
    if (_records[id]?.status != DownloadStatus.resolving) return null;

    if (saved != null) {
      // Tasks a kill left alive carry the old links.
      await _cancelTasksOf(id);
      if (_records[id]?.status != DownloadStatus.resolving) return null;
    }

    // The record as it is now: a refresh may have changed its metadata,
    // which is what a `CriteriaProvider` decides by.
    final current = _records[id]!;
    // The same choice for a fresh link; the request's for a changed one.
    final same = saved == null || current.replan
        ? null
        : resolved.selectionOf(saved);
    final plan = await resolved.plan(
      same ?? await _selectionFor(current, resolved),
    );
    // Planning an HLS reads its media playlists: a delete meanwhile must
    // not get its folder back from the plan being written.
    if (_records[id]?.status != DownloadStatus.resolving) return null;
    // Another encode or another choice: the pieces on disk are not these.
    if (saved != null && !plan.linesUpWith(saved)) await _wipePieces(id);
    await _writePlan(id, plan);
    final latest = _records[id];
    if (latest != null && latest.replan) _put(latest.copyWith(replan: false));
    return plan;
  }

  Future<SourceSelection> _selectionFor(
    DownloadRecord record,
    ResolvedSource source,
  ) async => switch (record.tracks) {
    PolicyChoice() => source.selectionFor(
      await _criteria?.call(record) ?? const TrackCriteria(),
    ),
    CriteriaChoice(:final criteria) => source.selectionFor(criteria),
    SelectionChoice(:final selection, :final fallback) =>
      _offers(source, selection) ? selection : source.selectionFor(fallback),
  };

  /// Whether [source] still has every track of [selection].
  static bool _offers(ResolvedSource source, SourceSelection selection) {
    final video = selection.videoId;
    final videos = {for (final v in source.videos) v.id};
    if (videos.isNotEmpty && !videos.contains(video)) return false;
    final audios = {for (final a in source.audiosFor(video)) a.id};
    final subtitles = {for (final s in source.subtitlesFor(video)) s.id};
    return audios.containsAll(selection.audioIds) &&
        subtitles.containsAll(selection.subtitleIds);
  }

  /// Keeps up to [_window] pieces with the downloader, refilled as they
  /// finish. One feeder per job at a time; calls meanwhile fold into it.
  Future<void> _feed(_Job job) async {
    if (job.feeding != null) {
      job.feedAgain = true;
      return job.feeding;
    }
    final feeding = job.feeding = _feedLoop(job);
    try {
      await feeding;
    } finally {
      job.feeding = null;
    }
  }

  Future<void> _feedLoop(_Job job) async {
    final record = _records[job.id];
    if (record == null) return;
    do {
      job.feedAgain = false;
      while (_jobs[job.id] == job && job.queue.isNotEmpty) {
        final room = min(_window - job.inFlight.length, _enqueueBatch);
        if (room <= 0) break;
        final batch = [
          for (var i = 0; i < room && job.queue.isNotEmpty; i++)
            job.queue.removeFirst(),
        ];
        final tasks = [
          for (final piece in batch) _taskFor(record, piece, job.run),
        ];
        // Counted before the answer, so a refill meanwhile sees the room
        // taken; a refused one is taken back, as the platform holds none.
        job.inFlight.addAll(tasks.map((t) => t.taskId));
        final results = await _transfer.enqueueAll(tasks);
        for (final (i, accepted) in results.indexed) {
          if (!accepted) job.inFlight.remove(tasks[i].taskId);
        }
        // A refused task would never report back: the download would wait
        // for it forever.
        if (results.contains(false)) {
          throw StateError('The downloader refused pieces of ${job.id}');
        }
        // Many enqueues in a row from a background app are what iOS
        // throttles; a breath between batches keeps them in front.
        if (job.queue.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    } while (job.feedAgain && _jobs[job.id] == job);
  }

  static const _enqueueBatch = 100;

  /// [_feed] from an update, failing the download on a refusal.
  void _feedSafely(_Job job) {
    unawaited(
      _feed(job).catchError((Object e, StackTrace st) {
        _logger.error(e, st, context: {'id': job.id, 'step': 'feed'});
        _failJob(job, const DownloadError(code: DownloadErrorCode.unknown));
      }),
    );
  }

  /// A piece that finished while the disk was being read had nobody to tell
  /// yet: without this the download would wait for an update that passed.
  /// Its file counts only when it can be told apart from one still being
  /// written: by its size, or because the platform moves files into place
  /// whole — otherwise only its `complete` update does.
  Future<void> _settleFinishedPieces(_Job job) async {
    for (final taskId in job.inFlight.toList()) {
      if (_jobs[job.id] != job) return;
      final piece = job.pieces[taskId]!;
      final file = File(
        p.join(_trackDir(job.id, piece.t).path, piece.planned.file),
      );
      final expected = piece.planned.expectedBytes;
      final done =
          _completedEarly.remove(taskId) ||
          (await file.exists() &&
              (expected != null
                  ? await _sizeOf(file) == expected
                  : _copiesInPlace));
      if (done) await _pieceDone(job, taskId, file);
    }
    _completedEarly.removeWhere((t) => _parseTaskId(t)?.id == job.id);
  }

  DownloadTask _taskFor(DownloadRecord record, _Piece piece, int run) {
    final range = piece.planned.rangeHeader;
    final whole = piece.isWholeFile;
    final task = DownloadTask(
      taskId: piece.taskId(record.id, run),
      url: piece.planned.url,
      headers: {
        ...?record.source.headers,
        'Range': ?range,
        if (range != null && piece.track.ifRange != null)
          'If-Range': piece.track.ifRange!,
      },
      filename: piece.planned.file,
      directory: p.join(config.rootFolder, record.id, 't${piece.t}'),
      baseDirectory: BaseDirectory.applicationSupport,
      group: whole
          ? PluginTransferClient.fileGroup
          : PluginTransferClient.pieceGroup,
      // Fragments are counted, not measured: thousands of progress ticks
      // would flood the channel.
      updates: whole || range != null
          ? Updates.statusAndProgress
          : Updates.status,
      retries: config.retries,
      // Held by the platform itself, so it never runs on mobile data while
      // the app sleeps; a change of the setting asks for it again.
      requiresWiFi: _requiresWifi,
      // Lets the plugin carry a long single request past Android's
      // nine-minute limit when the server allows ranges.
      allowPause: whole,
      displayName: record.title,
    );
    final dress = _hooks.onWholeFileTask;
    return whole && dress != null ? dress(task, record) : task;
  }

  // ---------------------------------------------------------------------
  // Downloader updates

  Future<void> _onStatus(TaskStatusUpdate update) async {
    final taskId = update.task.taskId;
    final ids = _parseTaskId(taskId);
    if (ids == null) return;
    final record = _records[ids.id];
    final job = _jobs[ids.id];

    // Not this run's (a task still being cancelled after a pause, one left
    // from a kill), or not followed (deleted, finished, or a replay of a
    // piece the disk already counts).
    if (job == null || job.run != ids.run || !job.pending.contains(taskId)) {
      final ofLastRun = record != null && ids.run == record.run;
      // Between a kill and its start: counted when its job is made.
      if (update.status == TaskStatus.complete && job == null && ofLastRun) {
        _completedEarly.add(taskId);
      }
      // Still running, or holding partial data, for nobody: let go.
      final stale =
          !_isMoving(record?.status) ||
          (record != null && ids.run < record.run);
      if ((update.status == TaskStatus.running ||
              update.status == TaskStatus.paused) &&
          stale) {
        await _transfer.cancelTasksWithIds([taskId]);
      }
      return;
    }

    switch (update.status) {
      case TaskStatus.complete:
        final piece = job.pieces[taskId]!;
        await _pieceDone(
          job,
          taskId,
          File(p.join(_trackDir(job.id, piece.t).path, piece.planned.file)),
        );
      // Cancelled by someone else — a notification's cancel button, or the
      // app through the plugin: the user stopping the download, which is a
      // pause, not a loss. The engine never cancels a task of the run it
      // follows, and a cancel of a piece not handed over (a late report) is
      // nobody's.
      case TaskStatus.canceled:
        if (job.inFlight.contains(taskId)) await pause(job.id);
      // Paused by the platform (whole files allow it): a notification's
      // pause button, which is the user's, or Android's background time
      // limit, which runs it again a moment later. Told apart by waiting.
      case TaskStatus.paused:
        _platformPauses.remove(taskId)?.cancel();
        _platformPauses[taskId] = Timer(config.platformPauseGrace, () {
          _platformPauses.remove(taskId);
          if (_jobs[job.id] == job && job.inFlight.contains(taskId)) {
            unawaited(pause(job.id));
          }
        });
      case TaskStatus.running:
        _platformPauses.remove(taskId)?.cancel();
      case TaskStatus.failed || TaskStatus.notFound
          when await _lostWifi(update):
        // Not a failure: back to the queue until Wi-Fi returns. Decided
        // once, by whichever piece reports first.
        if (_jobs[job.id] == job) _holdForWifi();
      case TaskStatus.failed || TaskStatus.notFound:
        final status =
            update.responseStatusCode ??
            switch (update.exception) {
              TaskHttpException(:final httpResponseCode) => httpResponseCode,
              _ => update.status == TaskStatus.notFound ? 404 : null,
            };
        final description = update.exception?.description ?? '';
        _logger.warn('piece $taskId failed: $status $description');
        // Over already: not cancelled with the rest.
        job.inFlight.remove(taskId);
        job.pending.remove(taskId);
        // 416: the range is outside the file — it is not the file planned.
        if (status == 416) {
          _failJob(
            job,
            const DownloadError(code: DownloadErrorCode.corrupt),
            wipe: true,
          );
          return;
        }
        _failJob(
          job,
          isOutOfSpace(description)
              ? const DownloadError(code: DownloadErrorCode.noSpace)
              : status != null && status >= 400
              ? DownloadError(code: DownloadErrorCode.http, httpStatus: status)
              : const DownloadError(code: DownloadErrorCode.network),
          // An expired or revoked link, whatever the clock says: the next
          // attempt asks the app for a fresh one.
          linkDead: const {401, 403, 404, 410}.contains(status),
        );
      default:
        break;
    }
  }

  void _onProgress(TaskProgressUpdate update) {
    final taskId = update.task.taskId;
    final ids = _parseTaskId(taskId);
    final job = ids == null ? null : _jobs[ids.id];
    if (job == null || !job.pending.contains(taskId)) return;
    if (update.progress < 0 || update.expectedFileSize <= 0) return;
    // The server answered something else than the piece planned — the
    // whole file for a range whose `If-Range` no longer matched, or a file
    // that changed: caught now, not after fetching all of it per range.
    final expected = job.pieces[taskId]!.planned.expectedBytes;
    if (expected != null && update.expectedFileSize != expected) {
      _failJob(
        job,
        const DownloadError(code: DownloadErrorCode.corrupt),
        wipe: true,
      );
      return;
    }
    job.received[taskId] = (update.progress * update.expectedFileSize).round();
    _publishProgress(job);
  }

  Future<void> _pieceDone(_Job job, String taskId, File file) async {
    if (!job.pending.contains(taskId)) return;
    // Measured before it leaves the pending set: the job may have moved on
    // meanwhile, and the count must stay exact.
    final size = await _sizeOf(file);
    if (_jobs[job.id] != job || !job.pending.remove(taskId)) return;
    job.inFlight.remove(taskId);
    job.received.remove(taskId);
    final piece = job.pieces[taskId]!;

    final expected = piece.planned.expectedBytes;
    if (expected != null && size != expected) {
      // The server ignored the range, the file changed under it, or a copy
      // was cut short. Every piece goes, and the plan with them: the next
      // attempt reads the source again, and old ranges of another version
      // of the file must not be spliced with new ones.
      _failJob(
        job,
        const DownloadError(code: DownloadErrorCode.corrupt),
        wipe: true,
      );
      return;
    }

    job.settledBytes += size;
    job.progress = job.progress.copyWith(
      donePieces: job.progress.donePieces + 1,
    );

    if (job.pending.isEmpty) {
      _jobs.remove(job.id);
      _publishProgress(job, force: true);
      await _assemble(job.id);
    } else {
      _publishProgress(job);
      _feedSafely(job);
    }
  }

  void _publishProgress(_Job job, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(job.lastEmit) < config.progressInterval) {
      return;
    }
    job.lastEmit = now;
    final record = _records[job.id];
    if (record == null || record.status != DownloadStatus.downloading) return;
    final received = job.received.values.fold(0, (a, b) => a + b);
    job.progress = job.progress.copyWith(bytes: job.settledBytes + received);
    // Not written to disk: the next start counts it again from the pieces.
    _put(record.copyWith(progress: job.progress), persist: false);
  }

  /// Fails the download [job] runs, unless it already moved on (paused,
  /// deleted, failed, or started again): decided at once, before anything
  /// is awaited, so a continuation never fails a newer attempt. The rest
  /// of its tasks are cancelled — and with [wipe], every piece and the plan
  /// removed — before the next start of the download may read its folder.
  void _failJob(
    _Job job,
    DownloadError error, {
    bool linkDead = false,
    bool wipe = false,
  }) {
    if (_jobs[job.id] != job) return;
    _fail(job.id, error, linkDead: linkDead);
    _track(job.id, () async {
      await _stop(job);
      if (wipe) await _wipePieces(job.id);
    });
  }

  /// Runs [body] as [id]'s clean-up (see [_cleanups]).
  void _track(String id, Future<void> Function() body) {
    final previous = _cleanups[id] ?? Future<void>.value();
    late final Future<void> done;
    done = previous
        .then((_) => body())
        .catchError(
          (Object e, StackTrace st) =>
              _logger.error(e, st, context: {'id': id, 'step': 'cleanup'}),
        )
        .whenComplete(() {
          if (identical(_cleanups[id], done)) _cleanups.remove(id);
        });
    _cleanups[id] = done;
  }

  /// Drops [id]'s job, if any, and cancels what it had handed over.
  Future<void> _stopJob(String id) async {
    final job = _jobs.remove(id);
    if (job != null) await _stop(job);
  }

  /// Waits for a batch being enqueued and cancels what [job] had handed
  /// over. Once per job.
  Future<void> _stop(_Job job) async {
    if (_jobs[job.id] == job) _jobs.remove(job.id);
    if (job.stopped) return;
    job.stopped = true;
    try {
      await job.feeding;
    } on Object {
      // Reported by whoever fed it.
    }
    await _transfer.cancelTasksWithIds(job.inFlight.toList());
    // A pause keeps the progress it had reached.
    final record = _records[job.id];
    if (record != null && record.run == job.run) {
      _put(record.copyWith(progress: job.progress));
    }
  }

  Future<void> _cancelTasksOf(String id) async {
    _recovering.remove(id);
    await _transfer.cancelTasksWithIds([
      for (final task in await _transfer.allTasks())
        if (_parseTaskId(task.taskId)?.id == id) task.taskId,
    ]);
  }

  // ---------------------------------------------------------------------
  // Assembly

  /// Packages or writes the one file of a download whose pieces are all on
  /// disk. Only one call per download gets past the claim.
  Future<void> _assemble(String id) async {
    if (!_transition(id, const {
      DownloadStatus.downloading,
    }, DownloadStatus.assembling)) {
      return;
    }
    try {
      final plan = await _readPlan(id);
      if (plan == null) {
        throw const SourceException(SourceErrorCode.missingPieces, 'no plan');
      }
      final record = _records[id]!;
      if (record.output.kind == OutputKind.package &&
          LocalPackager.supports(plan)) {
        final package = await _packager.package(plan, _workDir(id));
        _finish(
          id,
          locator:
              '$_workPrefix${p.relative(package.masterPath, from: _workDir(id).path)}',
          kind: OutputKind.package,
          bytes: package.bytes,
        );
      } else {
        await _exportFile(record, plan);
      }
    } catch (e, st) {
      _fail(id, _assemblyError(id, e, st));
    }
    unawaited(_pump());
  }

  /// What a failed package, merge or publish fails the download with;
  /// reported unless it is the disk being full.
  DownloadError _assemblyError(String id, Object e, StackTrace st) {
    final error = switch (e) {
      FfmpegException(:final log) when isOutOfSpace(log) => const DownloadError(
        code: DownloadErrorCode.noSpace,
      ),
      FfmpegException() => const DownloadError(code: DownloadErrorCode.mux),
      _PublishException() => const DownloadError(
        code: DownloadErrorCode.publish,
      ),
      _ => downloadErrorOf(e),
    };
    if (error.code != DownloadErrorCode.noSpace) {
      _logger.error(
        e is _PublishException ? e.cause : e,
        st,
        context: {
          'id': id,
          'step': 'assemble',
          if (e is FfmpegException) 'lastLine': _lastLine(e.log),
        },
      );
    }
    return error;
  }

  /// Writes the one file in the download's folder — merged, joined, or the
  /// source's own — then hands it to the sink. The file is a checkpoint: a
  /// kill or a failed publish after it only publishes again; and a sink
  /// that reserves its place lets a kill after the move find the file.
  Future<void> _exportFile(DownloadRecord record, DownloadPlan plan) async {
    final id = record.id;
    final work = _workDir(id);
    final staged = _stagedFile(id, plan);
    final sink = _sink;
    final reserving = sink is ReservingOutputSink ? sink : null;

    // Moved by a publish that a kill cut before the record said done.
    final target = record.publishTarget;
    if (reserving != null &&
        target != null &&
        await reserving.holds(target) &&
        (!await staged.exists() ||
            await _sizeOf(staged) == await _sizeOfLocator(id, target))) {
      await _deleteQuietly(staged);
      await _tidy(record, plan, staged, const []);
      await _finishFile(id, target);
      return;
    }

    if (!await staged.exists()) {
      final inputs = [
        for (final (t, track) in plan.tracks.indexed)
          await _assembler.assemble(track, _trackDir(id, t)),
      ];

      if (plan.needsMux) {
        final ffmpeg = _ffmpeg;
        if (ffmpeg == null) {
          throw const FfmpegException('No ffmpeg was given to the engine');
        }
        final partial = File(p.join(work.path, '.partial.${plan.extension}'));
        await ffmpeg.run(
          MkvArgs.build(
            inputs: inputs,
            outputPath: partial.path,
            title: record.title,
          ),
        );
        await partial.rename(staged.path);
      } else {
        await File(inputs.single.path).rename(staged.path);
      }

      final current = _records[id];
      if (current == null) return;
      _put(
        current.copyWith(stagedPath: '${_workPrefix}output.${plan.extension}'),
        persist: false,
      );
      await _store.save(_records[id]!);
      await _tidy(record, plan, staged, [
        for (final input in inputs)
          if (input.kind == TrackKind.subtitle) input,
      ]);
    } else {
      // Picked up after a kill or a failed publish: the pieces may still
      // be there, and the sidecars not listed yet.
      await _tidy(record, plan, staged, null);
    }

    // Measured before it goes: a sink may answer a locator that is not a
    // path (a content URI), and the file would finish weighing nothing.
    final size = await _sizeOf(staged);
    final String locator;
    try {
      final reserved = await reserving?.reserve(
        record.name,
        plan.extension,
        record,
      );
      if (reserved != null) {
        final current = _records[id];
        if (current == null) return;
        _put(current.copyWith(publishTarget: reserved), persist: false);
        await _store.save(_records[id]!);
        locator = await reserving!.publishTo(staged, reserved, record);
      } else {
        locator = await sink.publish(
          staged,
          record.name,
          plan.extension,
          record,
        );
      }
    } on Object catch (e) {
      throw _PublishException(e);
    }
    await _finishFile(id, locator, stagedSize: size);
  }

  Future<void> _finishFile(String id, String locator, {int? stagedSize}) async {
    final size = await _sizeOfLocator(id, locator) ?? stagedSize ?? 0;
    if (!_finish(id, locator: locator, kind: OutputKind.file, bytes: size)) {
      // Deleted while it was being written: nothing points at it any more.
      await _sink.remove(locator);
    }
  }

  /// A `work:` locator (the private sink's) is measured too: otherwise a
  /// file kept in the app's folder would finish weighing 0 bytes.
  Future<int?> _sizeOfLocator(String id, String locator) async {
    final path = locator.startsWith(_workPrefix)
        ? p.join(_workDir(id).path, locator.substring(_workPrefix.length))
        : (p.isAbsolute(locator) ? locator : null);
    return path == null ? null : _sizeOf(File(path));
  }

  /// Leaves the work folder with the record, the plan, [staged] and — when
  /// asked for — the subtitle sidecars in `subs/`, listed in
  /// `subtitles.json`. Idempotent, so a kill anywhere in it is finished by
  /// the next run: [sidecars] null means "work them out from what is on
  /// disk", which is what a start after a kill has.
  Future<void> _tidy(
    DownloadRecord record,
    DownloadPlan plan,
    File staged,
    List<MuxInput>? sidecars,
  ) async {
    final work = _workDir(record.id);
    final listed = File(p.join(work.path, _subtitlesFile));
    if (record.output.subtitleSidecars && !await listed.exists()) {
      final inputs =
          sidecars ??
          [
            for (final (t, track) in plan.tracks.indexed)
              if (track.kind == TrackKind.subtitle)
                ?await _assembleQuietly(track, _trackDir(record.id, t)),
          ];
      final subs = Directory(p.join(work.path, _subsDir));
      final kept = <PackagedSubtitle>[];
      for (final (i, s) in inputs.indexed) {
        await subs.create(recursive: true);
        final target = p.join(subs.path, '$i${p.extension(s.path)}');
        await File(s.path).rename(target);
        kept.add(
          PackagedSubtitle(
            path: p.relative(target, from: work.path),
            label: s.label,
            language: s.language,
            forced: s.forced,
          ),
        );
      }
      // Listed before the pieces go: a kill after this finds them done.
      if (kept.isNotEmpty) await LocalPackager.writeSubtitles(work, kept);
    }

    final keep = {
      p.normalize(staged.path),
      p.normalize(p.join(work.path, JsonRecordStore.recordFile)),
      p.normalize(p.join(work.path, _planFile)),
      p.normalize(listed.path),
      p.normalize(p.join(work.path, _subsDir)),
    };
    await for (final entity in work.list()) {
      if (keep.contains(p.normalize(entity.path))) continue;
      await _deleteQuietly(entity);
    }
  }

  Future<MuxInput?> _assembleQuietly(PlannedTrack track, Directory dir) async {
    try {
      return await _assembler.assemble(track, dir);
    } on SourceException {
      return null;
    }
  }

  /// Answers whether the record was still there to finish.
  bool _finish(
    String id, {
    required String locator,
    required OutputKind kind,
    required int bytes,
  }) => _transition(
    id,
    const {DownloadStatus.assembling},
    DownloadStatus.done,
    also: (r) => r.copyWith(
      outputLocator: locator,
      outputKind: kind,
      stagedPath: null,
      publishTarget: null,
      error: null,
      progress: r.progress.copyWith(
        bytes: bytes,
        totalBytes: bytes,
        donePieces: r.progress.totalPieces,
      ),
    ),
  );

  // ---------------------------------------------------------------------
  // Reconciliation

  /// The engine's tasks whose download is gone or not moving, or of a run
  /// before the record's last one: an ill-timed kill leaves them, and they
  /// would keep fetching into a folder nobody reads. Task ids from before
  /// runs were part of them do not parse, and go too.
  Future<void> _cancelStrayTasks() async {
    final stray = [
      for (final task in await _transfer.allTasks())
        if (_parseTaskId(task.taskId) case final ids
            when ids == null ||
                !_isMoving(_records[ids.id]?.status) ||
                ids.run != _records[ids.id]!.run)
          task.taskId,
    ];
    await _transfer.cancelTasksWithIds(stray);
  }

  static bool _isMoving(DownloadStatus? status) => switch (status) {
    DownloadStatus.queued ||
    DownloadStatus.resolving ||
    DownloadStatus.downloading => true,
    _ => false,
  };

  // ---------------------------------------------------------------------
  // Helpers

  /// Moves [id] to [to] only from one of [from] — and only [when] it holds
  /// — answering whether it did. Synchronous, so of two racing callers
  /// exactly one wins.
  bool _transition(
    String id,
    Set<DownloadStatus> from,
    DownloadStatus to, {
    DownloadRecord Function(DownloadRecord record)? also,
    bool Function(DownloadRecord record)? when,
  }) {
    if (_disposed) return false;
    final record = _records[id];
    if (record == null || !from.contains(record.status)) return false;
    if (when != null && !when(record)) return false;
    var next = record.copyWith(status: to);
    if (also != null) next = also(next);
    _put(next);
    return true;
  }

  void _fail(String id, DownloadError error, {bool linkDead = false}) {
    _jobs.remove(id);
    _transition(
      id,
      const {
        DownloadStatus.resolving,
        DownloadStatus.downloading,
        DownloadStatus.assembling,
      },
      DownloadStatus.failed,
      also: (r) => r.copyWith(
        error: error.copyWith(message: _compact(error.message)),
        linkDead: r.linkDead || linkDead,
      ),
    );
    unawaited(_pump());
  }

  void _put(DownloadRecord record, {bool persist = true}) {
    // See [dispose].
    if (_disposed) return;
    final next = record.copyWith(updatedAt: DateTime.now());
    _records[next.id] = next;
    if (persist) {
      unawaited(
        _store
            .save(next)
            .catchError(
              (Object e, StackTrace st) => _logger.error(
                e,
                st,
                context: {'id': next.id, 'step': 'save'},
              ),
            ),
      );
    }
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Directory _workDir(String id) => Directory(p.join(_root.path, id));

  Directory _trackDir(String id, int track) =>
      Directory(p.join(_root.path, id, 't$track'));

  Future<DownloadPlan?> _readPlan(String id) async {
    final file = File(p.join(_workDir(id).path, _planFile));
    if (!await file.exists()) return null;
    try {
      return DownloadPlan.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on Object {
      // Unreadable: planned again from the source.
      return null;
    }
  }

  Future<void> _writePlan(String id, DownloadPlan plan) async {
    final file = File(p.join(_workDir(id).path, _planFile));
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(plan.toJson()), flush: true);
    await temp.rename(file.path);
  }

  /// Everything in the folder but the record.
  Future<void> _wipePieces(String id) async {
    final work = _workDir(id);
    if (!await work.exists()) return;
    final record = p.normalize(p.join(work.path, JsonRecordStore.recordFile));
    await for (final entity in work.list()) {
      if (p.normalize(entity.path) != record) await _deleteQuietly(entity);
    }
  }

  /// The one file of a failed attempt (`output.<ext>`), and its sidecars.
  Future<void> _deleteStaged(String id) async {
    final work = _workDir(id);
    if (!await work.exists()) return;
    await for (final entity in work.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith('output.') ||
          name == _subtitlesFile ||
          name == _subsDir) {
        await _deleteQuietly(entity);
      }
    }
  }

  /// Name → size of the files in [dir]; empty when it does not exist yet.
  Future<Map<String, int>> _sizesIn(Directory dir) async {
    if (!await dir.exists()) return const {};
    return {
      await for (final entity in dir.list())
        if (entity is File) p.basename(entity.path): await entity.length(),
    };
  }

  static Future<int> _sizeOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException catch (e) {
      _logger.warn('could not delete ${entity.path}: $e');
    }
  }

  static String? _lastLine(String log) {
    for (final line in log.trim().split('\n').reversed) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return null;
  }

  /// What a two-line list row can show; never a wall of text.
  static String? _compact(String? message, {int max = 200}) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  static final _random = Random.secure();

  /// Time-ordered and never reused, in characters every platform takes in
  /// a folder name and a task id.
  static String _newId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '$time$noise';
  }

  /// `ode-<id>-<run>-<track>-<piece>`.
  static ({String id, int run, int track, int piece})? _parseTaskId(
    String taskId,
  ) {
    final parts = taskId.split('-');
    if (parts.length != 5 || parts.first != _taskPrefix) return null;
    final run = int.tryParse(parts[2]);
    final track = int.tryParse(parts[3]);
    final piece = int.tryParse(parts[4]);
    if (run == null || track == null || piece == null) return null;
    return (id: parts[1], run: run, track: track, piece: piece);
  }

  static const _taskPrefix = 'ode';
}

class _Piece {
  _Piece(this.t, this.index, this.track, this.planned);

  /// The track's index in the plan, and the piece's in the track.
  final int t;
  final int index;
  final PlannedTrack track;
  final PlannedPiece planned;

  /// A file fetched in one request, followed by bytes and paused by the
  /// downloader itself.
  bool get isWholeFile =>
      track.assembly == TrackAssembly.single && planned.rangeStart == null;

  String taskId(String id, int run) =>
      '${DownloadEngine._taskPrefix}-$id-$run-$t-$index';
}

/// The download in flight, in memory: one run of it.
class _Job {
  _Job({
    required this.id,
    required this.run,
    required this.plan,
    required this.progress,
    required this.settledBytes,
  });

  final String id;

  /// See `DownloadRecord.run`.
  final int run;
  final DownloadPlan plan;
  DownloadProgress progress;
  int settledBytes;

  final Map<String, _Piece> pieces = {};

  /// Not on disk yet.
  final Set<String> pending = {};

  /// Handed to the downloader and not finished.
  final Set<String> inFlight = {};

  /// Waiting for room in the window.
  final Queue<_Piece> queue = Queue();

  /// Bytes received by the pieces followed by bytes.
  final Map<String, int> received = {};
  DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void>? feeding;
  bool feedAgain = false;

  /// Its tasks were cancelled (see `DownloadEngine._stop`).
  bool stopped = false;
}

class _PublishException implements Exception {
  const _PublishException(this.cause);

  final Object cause;
}
