import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:offline_engine/src/engine/errors.dart';
import 'package:offline_engine/src/engine/extension_points.dart';
import 'package:offline_engine/src/engine/model.dart';
import 'package:offline_engine/src/engine/output_sinks.dart';
import 'package:offline_engine/src/engine/record_store.dart';
import 'package:offline_engine/src/engine/transfer_client.dart';
import 'package:offline_engine/src/planner/assembly/local_packager.dart';
import 'package:offline_engine/src/planner/assembly/mkv_args.dart';
import 'package:offline_engine/src/planner/assembly/mux_input.dart';
import 'package:offline_engine/src/planner/assembly/track_assembler.dart';
import 'package:offline_engine/src/planner/errors.dart';
import 'package:offline_engine/src/planner/media_options.dart';
import 'package:offline_engine/src/planner/plan.dart';
import 'package:offline_engine/src/planner/sources/resolved_source.dart';
import 'package:offline_engine/src/planner/sources/source_resolver.dart';
import 'package:offline_engine/src/planner/track_criteria.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tuning, with defaults that suit every platform.
class EngineConfig {
  const EngineConfig({
    this.rootFolder = 'offline_engine',
    this.maxConcurrent = 8,
    this.window,
    this.retries = 3,
    this.progressInterval = const Duration(milliseconds: 500),
    this.linkMargin = const Duration(minutes: 30),
    this.foregroundAboveMb,
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
  final EngineLogger _logger;
  final TransferClient _transfer;
  final SourceResolver _resolver;
  final Future<Directory> Function() _appSupport;
  final RecordStore? _storeOverride;
  late final RecordStore _store;

  static const _packager = LocalPackager();
  static const _assembler = TrackAssembler();
  static const _planFile = 'plan.json';
  static const _master = 'master.m3u8';

  /// Prefix of a locator inside the download's own folder: stored relative,
  /// because the container path changes on iOS between installs.
  static const _workPrefix = 'work:';

  late Directory _root;
  final Map<String, DownloadRecord> _records = {};
  final Map<String, _Job> _jobs = {};

  /// Tasks the engine cancelled itself, whose `canceled` update is not a
  /// reason to ask for them again.
  final Set<String> _ownCancels = {};

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

  // ---------------------------------------------------------------------
  // Life

  /// Idempotent. Loads the records, picks up what a kill left behind and
  /// starts the queue — so call it at app start, not when a screen opens.
  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    _root = Directory(p.join((await _appSupport()).path, config.rootFolder));
    _store = _storeOverride ?? JsonRecordStore(() async => _root);

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

    await _cancelStrayTasks();
    for (final record in _records.values.toList()) {
      if (record.isActive) {
        _put(record.copyWith(status: DownloadStatus.queued));
      }
    }
    _emit();
    unawaited(_pump());
  }

  Future<void> _whenReady() async {
    try {
      await _ready;
    } on Object {
      // Reported by whoever started init.
    }
  }

  /// Stops reporting. Tasks keep running in the platform; the next engine
  /// picks them up.
  Future<void> dispose() async {
    _disposed = true;
    _jobs.clear();
    await _changes.close();
  }

  // ---------------------------------------------------------------------
  // Reading

  /// Newest first.
  List<DownloadRecord> get records =>
      _records.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  DownloadRecord? byId(String id) => _records[id];

  DownloadRecord? byKey(String key) =>
      _records.values.where((r) => r.key == key).firstOrNull;

  /// [records] now and after every change.
  Stream<List<DownloadRecord>> watchAll() async* {
    await _whenReady();
    yield records;
    yield* _changes.stream.map((_) => records);
  }

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
  Future<EnqueueResult> enqueue(DownloadRequest request) async {
    await _whenReady();
    final now = DateTime.now();
    final existing = byKey(request.key);

    if (existing != null && existing.status != DownloadStatus.failed) {
      return (id: existing.id, outcome: EnqueueOutcome.existing);
    }

    final id = existing?.id ?? _newId();
    final plan = request.plan;
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
            linkDead: false,
            tracks: request.tracks,
            output: request.output,
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
  /// what it published.
  Future<void> delete(String id) async {
    await _whenReady();
    final record = _records.remove(id);
    if (record == null) return;
    _emit();
    await _stopJob(id);

    final locator = record.outputLocator;
    if (locator != null && !locator.startsWith(_workPrefix)) {
      try {
        await _sink.remove(locator);
      } on Object catch (e, st) {
        _logger.error(e, st, context: {'id': id, 'step': 'remove'});
      }
    }
    await _store.delete(id);
    await _deleteQuietly(_workDir(id));
    unawaited(_pump());
  }

  /// Deletes everything not finished. Answers how many went.
  Future<int> cancelPending() async {
    await _whenReady();
    final pending = [
      for (final r in _records.values)
        if (r.status != DownloadStatus.done) r.id,
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
          final next =
              (_records.values
                      .where((r) => r.status == DownloadStatus.queued)
                      .toList()
                    ..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
                  .firstOrNull;
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

    final plan = await _planFor(id);
    if (plan == null || _records[id]?.status != DownloadStatus.resolving) {
      return;
    }

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
        // A range cut short (a copy interrupted on desktop): asked again.
        if (size != null) {
          await _deleteQuietly(File(p.join(_trackDir(id, t).path, piece.file)));
        }
        missing.add(_Piece(t, i, track, piece));
      }
    }

    final progress = DownloadProgress(
      donePieces: plan.pieceCount - missing.length,
      totalPieces: plan.pieceCount,
      bytes: settledBytes,
      totalBytes: plan.expectedBytes,
      segmented: plan.isSegmented,
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

    // What the platform still holds after a kill is not asked for twice.
    final alive = {
      for (final task in await _transfer.allTasks())
        if (_parseTaskId(task.taskId)?.id == id) task.taskId,
    };
    if (_records[id]?.status != DownloadStatus.downloading) return;

    final job = _jobs[id] = _Job(
      id: id,
      plan: plan,
      progress: progress,
      settledBytes: settledBytes,
    );
    for (final piece in missing) {
      final taskId = piece.taskId(id);
      job.pieces[taskId] = piece;
      job.pending.add(taskId);
      if (alive.contains(taskId)) {
        job.inFlight.add(taskId);
      } else {
        job.queue.add(piece);
      }
    }

    await _feed(job);
    await _settleFinishedPieces(job);
  }

  /// The plan on disk, or a new one. A plan whose link ran out is planned
  /// again from a fresh link with the same choice, keeping the pieces on
  /// disk when they are the same files; otherwise it starts over.
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
    if (saved != null && !expired) return saved;

    var source = record.source;
    final refresher = _refresher;
    if (expired && refresher != null) {
      final fresh = await refresher.refresh(record);
      final current = _records[id];
      if (current?.status != DownloadStatus.resolving) return null;
      _put(
        current!.copyWith(
          source: fresh.source,
          expiresAt: fresh.expiresAt,
          linkDead: false,
          metadata: fresh.metadata ?? current.metadata,
        ),
      );
      source = fresh.source;
    }

    final resolved = await _resolver.resolve(source);
    if (_records[id]?.status != DownloadStatus.resolving) return null;

    if (saved != null) {
      // Tasks a kill left alive carry the old links.
      await _cancelTasksOf(id);
      final same = resolved.selectionOf(saved);
      if (same != null) {
        final replanned = await resolved.plan(same);
        if (replanned.linesUpWith(saved)) {
          await _writePlan(id, replanned);
          return replanned;
        }
      }
      // Another encode or another choice: the pieces on disk are not these.
      await _wipePieces(id);
    }

    final plan = await resolved.plan(await _selectionFor(record, resolved));
    if (_records[id]?.status != DownloadStatus.resolving) return null;
    await _writePlan(id, plan);
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
        final tasks = [for (final piece in batch) _taskFor(record, piece)];
        job.inFlight.addAll(tasks.map((t) => t.taskId));
        final results = await _transfer.enqueueAll(tasks);
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
      _feed(job).catchError((Object e, StackTrace st) async {
        _logger.error(e, st, context: {'id': job.id, 'step': 'feed'});
        await _stopJob(job.id);
        _fail(job.id, const DownloadError(code: DownloadErrorCode.unknown));
      }),
    );
  }

  /// A piece that finished while the disk was being read had nobody to tell
  /// yet: without this the download would wait for an update that passed.
  Future<void> _settleFinishedPieces(_Job job) async {
    for (final taskId in job.inFlight.toList()) {
      if (_jobs[job.id] != job) return;
      final piece = job.pieces[taskId]!;
      final file = File(
        p.join(_trackDir(job.id, piece.t).path, piece.planned.file),
      );
      if (await file.exists()) await _pieceDone(job, taskId, file);
    }
  }

  DownloadTask _taskFor(DownloadRecord record, _Piece piece) {
    final range = piece.planned.rangeHeader;
    final whole = piece.isWholeFile;
    final task = DownloadTask(
      taskId: piece.taskId(record.id),
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
    final job = _jobs[ids.id];

    if (update.status == TaskStatus.canceled && _ownCancels.remove(taskId)) {
      return;
    }

    // Not followed (paused, deleted, finished, or a replay of a piece the
    // disk already counts). A piece still running for a download that is
    // not moving has nowhere to go.
    if (job == null || !job.pending.contains(taskId)) {
      if (update.status == TaskStatus.running &&
          !_isMoving(_records[ids.id]?.status)) {
        await _cancel([taskId]);
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
      // Cancelled by someone else (a notification button, the system): the
      // download would wait for it forever, so it is asked for again.
      case TaskStatus.canceled:
        if (update.task case final DownloadTask task) {
          await _transfer.enqueueAll([task]);
        }
      case TaskStatus.failed || TaskStatus.notFound:
        await _stopJob(job.id);
        final status =
            update.responseStatusCode ??
            switch (update.exception) {
              TaskHttpException(:final httpResponseCode) => httpResponseCode,
              _ => update.status == TaskStatus.notFound ? 404 : null,
            };
        final description = update.exception?.description ?? '';
        _logger.warn('piece $taskId failed: $status $description');
        _fail(
          job.id,
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
    final ids = _parseTaskId(update.task.taskId);
    final job = ids == null ? null : _jobs[ids.id];
    if (job == null || !job.pending.contains(update.task.taskId)) return;
    if (update.progress < 0 || update.expectedFileSize <= 0) return;
    job.received[update.task.taskId] =
        (update.progress * update.expectedFileSize).round();
    _publishProgress(job);
  }

  Future<void> _pieceDone(_Job job, String taskId, File file) async {
    if (!job.pending.remove(taskId)) return;
    job.inFlight.remove(taskId);
    job.received.remove(taskId);
    final piece = job.pieces[taskId]!;
    final size = await _sizeOf(file);

    final expected = piece.planned.expectedBytes;
    if (expected != null && size != expected) {
      // The server ignored the range, or the file changed under it. The
      // plan goes too: the next attempt reads the source again.
      await _stopJob(job.id);
      await _deleteQuietly(file);
      await _deleteQuietly(File(p.join(_workDir(job.id).path, _planFile)));
      _fail(job.id, const DownloadError(code: DownloadErrorCode.corrupt));
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

  /// Drops the job, waits for a batch being enqueued, and cancels what it
  /// had handed over.
  Future<void> _stopJob(String id) async {
    final job = _jobs.remove(id);
    if (job == null) return;
    try {
      await job.feeding;
    } on Object {
      // Reported by whoever fed it.
    }
    await _cancel(job.inFlight.toList());
    // A pause keeps the progress it had reached.
    final record = _records[id];
    if (record != null) _put(record.copyWith(progress: job.progress));
  }

  Future<void> _cancel(List<String> taskIds) async {
    if (taskIds.isEmpty) return;
    _ownCancels.addAll(taskIds);
    await _transfer.cancelTasksWithIds(taskIds);
  }

  Future<void> _cancelTasksOf(String id) async => _cancel([
    for (final task in await _transfer.allTasks())
      if (_parseTaskId(task.taskId)?.id == id) task.taskId,
  ]);

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
      final error = switch (e) {
        FfmpegException(:final log) when isOutOfSpace(log) =>
          const DownloadError(code: DownloadErrorCode.noSpace),
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
      _fail(id, error);
    }
    unawaited(_pump());
  }

  /// Writes the one file in the download's folder — merged, joined, or the
  /// source's own — then hands it to the sink. The file is a checkpoint: a
  /// kill or a failed publish after it only publishes again.
  Future<void> _exportFile(DownloadRecord record, DownloadPlan plan) async {
    final id = record.id;
    final work = _workDir(id);
    final staged = File(p.join(work.path, 'output.${plan.extension}'));

    if (!(record.stagedPath != null && await staged.exists())) {
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

      final sidecars = record.output.subtitleSidecars
          ? [
              for (final input in inputs)
                if (input.kind == TrackKind.subtitle) input,
            ]
          : const <MuxInput>[];
      await _keepOnly(work, staged, sidecars);
      final current = _records[id];
      if (current == null) return;
      _put(
        current.copyWith(stagedPath: '${_workPrefix}output.${plan.extension}'),
      );
    }

    final String locator;
    try {
      locator = await _sink.publish(
        staged,
        record.name,
        plan.extension,
        record,
      );
    } on Object catch (e) {
      throw _PublishException(e);
    }
    final size = await _sizeOfLocator(locator) ?? 0;
    if (!_finish(id, locator: locator, kind: OutputKind.file, bytes: size)) {
      // Deleted while it was being written: nothing points at it any more.
      await _sink.remove(locator);
    }
  }

  Future<int?> _sizeOfLocator(String locator) async {
    final path = locator.startsWith(_workPrefix)
        ? null
        : (p.isAbsolute(locator) ? locator : null);
    return path == null ? null : _sizeOf(File(path));
  }

  /// Removes everything in [work] but the record, [staged] and the
  /// [sidecars], which move to `subs/` and are listed in `subtitles.json`.
  Future<void> _keepOnly(
    Directory work,
    File staged,
    List<MuxInput> sidecars,
  ) async {
    final subs = Directory(p.join(work.path, 'subs'));
    final kept = <PackagedSubtitle>[];
    for (final (i, s) in sidecars.indexed) {
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

    final keep = {
      p.normalize(staged.path),
      p.normalize(p.join(work.path, JsonRecordStore.recordFile)),
      p.normalize(p.join(work.path, _planFile)),
    };
    await for (final entity in work.list()) {
      final path = p.normalize(entity.path);
      if (keep.contains(path) || path == p.normalize(subs.path)) continue;
      await _deleteQuietly(entity);
    }
    if (kept.isNotEmpty) await LocalPackager.writeSubtitles(work, kept);
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

  /// The engine's tasks whose download is gone or not moving: an ill-timed
  /// kill leaves them, and they would keep fetching into a folder nobody
  /// reads.
  Future<void> _cancelStrayTasks() async {
    final stray = [
      for (final task in await _transfer.allTasks())
        if (!_isMoving(_records[_parseTaskId(task.taskId)?.id]?.status))
          task.taskId,
    ];
    await _cancel(stray);
  }

  static bool _isMoving(DownloadStatus? status) => switch (status) {
    DownloadStatus.queued ||
    DownloadStatus.resolving ||
    DownloadStatus.downloading => true,
    _ => false,
  };

  // ---------------------------------------------------------------------
  // Helpers

  /// Moves [id] to [to] only from one of [from], answering whether it did.
  /// Synchronous, so of two racing callers exactly one wins.
  bool _transition(
    String id,
    Set<DownloadStatus> from,
    DownloadStatus to, {
    DownloadRecord Function(DownloadRecord record)? also,
  }) {
    final record = _records[id];
    if (record == null || !from.contains(record.status)) return false;
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

  static ({String id, int track, int piece})? _parseTaskId(String taskId) {
    final parts = taskId.split('-');
    if (parts.length != 4 || parts.first != _taskPrefix) return null;
    final track = int.tryParse(parts[2]);
    final piece = int.tryParse(parts[3]);
    if (track == null || piece == null) return null;
    return (id: parts[1], track: track, piece: piece);
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

  String taskId(String id) => '${DownloadEngine._taskPrefix}-$id-$t-$index';
}

/// The download in flight, in memory.
class _Job {
  _Job({
    required this.id,
    required this.plan,
    required this.progress,
    required this.settledBytes,
  });

  final String id;
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
}

class _PublishException implements Exception {
  const _PublishException(this.cause);

  final Object cause;
}
