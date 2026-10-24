import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:offline_engine/src/planner/media_options.dart';
import 'package:offline_engine/src/planner/plan.dart';
import 'package:offline_engine/src/planner/sources/source_request.dart';
import 'package:offline_engine/src/planner/track_criteria.dart';

part 'model.freezed.dart';
part 'model.g.dart';

/// Where a download is in its life.
enum DownloadStatus {
  queued,

  /// Reading the source and planning its pieces — after asking the app for
  /// a fresh link when the one on the record ran out.
  resolving,
  downloading,
  paused,

  /// Every piece is on disk: writing the local package, or the one file.
  assembling,
  done,
  failed,
}

/// Which tracks a download keeps.
@immutable
sealed class TrackChoice {
  const TrackChoice();

  /// Whatever the app's `CriteriaProvider` says when the download's turn
  /// comes — so a queued season follows the settings of that moment.
  const factory TrackChoice.policy() = PolicyChoice;

  const factory TrackChoice.criteria(TrackCriteria criteria) = CriteriaChoice;

  /// The ids the user picked from the source. When a fresh link no longer
  /// has them, [fallback] picks again.
  const factory TrackChoice.selection(
    SourceSelection selection, {
    TrackCriteria fallback,
  }) = SelectionChoice;

  factory TrackChoice.fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'criteria' => CriteriaChoice(
          TrackCriteria.fromJson(json['criteria']! as Map<String, Object?>),
        ),
        // Without a fallback, the default one: a record that cannot be read
        // is dropped with its folder (see `JsonRecordStore.loadAll`).
        'selection' => SelectionChoice(
          SourceSelection.fromJson(json['selection']! as Map<String, Object?>),
          fallback: switch (json['fallback']) {
            final Map<String, Object?> fallback => TrackCriteria.fromJson(
              fallback,
            ),
            _ => const TrackCriteria(),
          },
        ),
        _ => const PolicyChoice(),
      };

  Map<String, Object?> toJson();
}

final class PolicyChoice extends TrackChoice {
  const PolicyChoice();

  @override
  Map<String, Object?> toJson() => {'type': 'policy'};

  @override
  bool operator ==(Object other) => other is PolicyChoice;

  @override
  int get hashCode => 0;
}

final class CriteriaChoice extends TrackChoice {
  const CriteriaChoice(this.criteria);

  final TrackCriteria criteria;

  @override
  Map<String, Object?> toJson() => {
    'type': 'criteria',
    'criteria': criteria.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CriteriaChoice && other.criteria == criteria;

  @override
  int get hashCode => criteria.hashCode;
}

final class SelectionChoice extends TrackChoice {
  const SelectionChoice(
    this.selection, {
    this.fallback = const TrackCriteria(),
  });

  final SourceSelection selection;
  final TrackCriteria fallback;

  @override
  Map<String, Object?> toJson() => {
    'type': 'selection',
    'selection': selection.toJson(),
    'fallback': fallback.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SelectionChoice &&
      other.selection == selection &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(selection, fallback);
}

/// What a finished download is left as.
enum OutputKind {
  /// A local HLS (`master.m3u8`) beside its pieces, which players open as
  /// is. Only for fragmented sources; anything else becomes a [file].
  package,

  /// One file: the source's own, or every track merged into an MKV.
  file,
}

/// What a download is asked to become.
@freezed
abstract class OutputMode with _$OutputMode {
  const factory OutputMode({
    @Default(OutputKind.package) OutputKind kind,

    /// With [OutputKind.file], whether the subtitles also stay beside the
    /// file — some players only style subtitles loaded from outside.
    @Default(false) bool subtitleSidecars,
  }) = _OutputMode;

  factory OutputMode.fromJson(Map<String, Object?> json) =>
      _$OutputModeFromJson(json);

  static const package = OutputMode();
  static const file = OutputMode(kind: OutputKind.file);
}

/// What a finished file is called and where it is filed, as the app wants
/// it: `['Loki', 'Season 01']` + `Loki S01E01`. The extension is the
/// engine's to add.
@freezed
abstract class OutputName with _$OutputName {
  const factory OutputName({
    required String baseName,
    @Default([]) List<String> folders,
  }) = _OutputName;

  factory OutputName.fromJson(Map<String, Object?> json) =>
      _$OutputNameFromJson(json);
}

@freezed
abstract class DownloadProgress with _$DownloadProgress {
  const DownloadProgress._();

  const factory DownloadProgress({
    @Default(0) int donePieces,
    @Default(0) int totalPieces,
    @Default(0) int bytes,
    @Default(0) int totalBytes,

    /// Counted by pieces rather than bytes: a fragmented source's weight is
    /// only an estimate from its bitrate.
    @Default(false) bool segmented,
  }) = _DownloadProgress;

  factory DownloadProgress.fromJson(Map<String, Object?> json) =>
      _$DownloadProgressFromJson(json);

  /// 0–1, or null before there is anything to measure.
  double? get fraction {
    if (segmented) {
      return totalPieces > 0
          ? (donePieces / totalPieces).clamp(0.0, 1.0)
          : null;
    }
    return totalBytes > 0 ? (bytes / totalBytes).clamp(0.0, 1.0) : null;
  }
}

/// Why a download failed: a [DownloadErrorCode] the app localizes, and
/// what the server or the app said, when there is something worth showing.
@freezed
abstract class DownloadError with _$DownloadError {
  const factory DownloadError({
    required String code,
    String? message,
    int? httpStatus,
  }) = _DownloadError;

  factory DownloadError.fromJson(Map<String, Object?> json) =>
      _$DownloadErrorFromJson(json);
}

class _SourceConverter
    implements JsonConverter<SourceRequest, Map<String, Object?>> {
  const _SourceConverter();

  @override
  SourceRequest fromJson(Map<String, Object?> json) =>
      SourceRequest.fromJson(json);

  @override
  Map<String, Object?> toJson(SourceRequest object) => object.toJson();
}

class _TrackChoiceConverter
    implements JsonConverter<TrackChoice, Map<String, Object?>> {
  const _TrackChoiceConverter();

  @override
  TrackChoice fromJson(Map<String, Object?> json) => TrackChoice.fromJson(json);

  @override
  Map<String, Object?> toJson(TrackChoice object) => object.toJson();
}

/// One download, as the engine keeps it. Immutable with value equality, so
/// a UI can watch one field of it.
@freezed
abstract class DownloadRecord with _$DownloadRecord {
  const DownloadRecord._();

  const factory DownloadRecord({
    /// The engine's own id, never reused; also the name of its folder.
    required String id,

    /// The app's identity for what is downloaded, unique among records:
    /// asking for the same key again finds this record.
    required String key,

    /// What the download is shown and merged as.
    required String title,
    required OutputName name,

    /// The app's own data, kept and handed back as is.
    @Default({}) Map<String, Object?> metadata,
    required DownloadStatus status,
    DownloadError? error,
    @_SourceConverter() required SourceRequest source,

    /// When the source's link stops working, when the app knows it.
    DateTime? expiresAt,

    /// The server refused the source's link: the next attempt asks the app
    /// for a fresh one, whatever [expiresAt] says.
    @Default(false) bool linkDead,
    @_TrackChoiceConverter() @Default(TrackChoice.policy()) TrackChoice tracks,
    @Default(OutputMode()) OutputMode output,

    /// The finished download: the package's master playlist or the file, as
    /// the output sink stored it (a path, or whatever the sink understands).
    String? outputLocator,
    OutputKind? outputKind,

    /// The one file, written and not yet handed to the output sink: what a
    /// kill between the two picks up from instead of merging again.
    String? stagedPath,
    @Default(DownloadProgress()) DownloadProgress progress,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _DownloadRecord;

  factory DownloadRecord.fromJson(Map<String, Object?> json) =>
      _$DownloadRecordFromJson(json);

  bool get isActive => switch (status) {
    DownloadStatus.resolving ||
    DownloadStatus.downloading ||
    DownloadStatus.assembling => true,
    _ => false,
  };
}

/// One title to put in the queue.
@immutable
class DownloadRequest {
  const DownloadRequest({
    required this.key,
    required this.title,
    required this.name,
    required this.source,
    this.expiresAt,
    this.tracks = const TrackChoice.policy(),
    this.plan,
    this.output = OutputMode.package,
    this.metadata = const {},
  });

  /// See [DownloadRecord.key].
  final String key;
  final String title;
  final OutputName name;
  final SourceRequest source;
  final DateTime? expiresAt;
  final TrackChoice tracks;

  /// Already planned — after the user picked tracks from the source —
  /// rather than at the download's turn.
  final DownloadPlan? plan;
  final OutputMode output;
  final Map<String, Object?> metadata;
}

enum EnqueueOutcome {
  /// A new record.
  created,

  /// One for the key was already there, offline or on its way: left alone.
  existing,

  /// One for the key had failed: it starts again with the new source.
  replacedFailed,
}

typedef EnqueueResult = ({String id, EnqueueOutcome outcome});
