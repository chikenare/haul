import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/model.dart';

/// One row of a downloads list: a download on its own, or a parent with
/// its children.
///
/// Holds ids, not records: the shape of the list only changes when a
/// download comes, goes or moves, not on every progress tick, so a list
/// built from it is rebuilt only then and each row watches its own record.
@immutable
sealed class DownloadEntry {
  const DownloadEntry();

  /// Every download in it, in list order.
  List<String> get ids;
}

final class SingleDownload extends DownloadEntry {
  const SingleDownload(this.id);

  final String id;

  @override
  List<String> get ids => [id];

  @override
  bool operator ==(Object other) => other is SingleDownload && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class ParentDownloads extends DownloadEntry {
  const ParentDownloads(this.parent, this.ids);

  final DownloadParent parent;

  /// Its children, by title in natural order (`S01E02` before `S01E10`).
  @override
  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is ParentDownloads &&
      other.parent == parent &&
      const ListEquality<String>().equals(other.ids, ids);

  @override
  int get hashCode =>
      Object.hash(parent, const ListEquality<String>().hash(ids));
}

/// [records] as a list: parents and loose downloads together, newest first
/// (a parent counts by its newest child).
List<DownloadEntry> downloadEntries(Iterable<DownloadRecord> records) {
  final loose = <DownloadRecord>[];
  final children = <String, List<DownloadRecord>>{};
  for (final r in records) {
    final parent = r.parent;
    if (parent == null) {
      loose.add(r);
    } else {
      (children[parent.id] ??= []).add(r);
    }
  }

  final entries = <(DateTime, DownloadEntry)>[
    for (final r in loose) (r.createdAt, SingleDownload(r.id)),
    for (final members in children.values) _parentEntry(members),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final e in entries) e.$2];
}

(DateTime, DownloadEntry) _parentEntry(List<DownloadRecord> children) {
  final newest = children.reduce(
    (a, b) => b.createdAt.isAfter(a.createdAt) ? b : a,
  );
  return (
    newest.createdAt,
    ParentDownloads(newest.parent!, [
      for (final r in children.sorted(compareByTitle)) r.id,
    ]),
  );
}

/// By title in natural order — numbers as numbers, so `S01E02` comes
/// before `S01E10` — then by when they were asked for. Downloading
/// episode 3 before episode 1 does not put it first.
int compareByTitle(DownloadRecord a, DownloadRecord b) {
  final byTitle = compareAsciiLowerCaseNatural(a.title, b.title);
  return byTitle != 0 ? byTitle : a.createdAt.compareTo(b.createdAt);
}

/// How far a set of downloads is — a parent's children, or some of them —
/// for a show's row or a season's button.
@immutable
class ParentProgress {
  const ParentProgress({
    required this.total,
    required this.done,
    required this.active,
    required this.paused,
    required this.failed,
    required this.bytes,
    required this.totalBytes,
    required this.fraction,
  });

  /// Of [records]: each download counts the same, so a short episode is
  /// not drowned by a long one whose size is only an estimate.
  factory ParentProgress.of(Iterable<DownloadRecord> records) {
    var total = 0, done = 0, active = 0, paused = 0, failed = 0;
    var bytes = 0, totalBytes = 0;
    var sum = 0.0;
    for (final r in records) {
      total++;
      bytes += r.progress.bytes;
      totalBytes += r.progress.totalBytes;
      switch (r.status) {
        case DownloadStatus.done:
          done++;
          sum += 1;
          continue;
        case DownloadStatus.paused:
          paused++;
        case DownloadStatus.failed:
          failed++;
        case DownloadStatus.queued ||
            DownloadStatus.resolving ||
            DownloadStatus.downloading ||
            DownloadStatus.assembling:
          active++;
      }
      sum += r.progress.fraction ?? 0;
    }
    return ParentProgress(
      total: total,
      done: done,
      active: active,
      paused: paused,
      failed: failed,
      bytes: bytes,
      totalBytes: totalBytes,
      fraction: total == 0 ? 0 : sum / total,
    );
  }

  final int total;
  final int done;

  /// Queued, preparing, downloading or finishing.
  final int active;
  final int paused;
  final int failed;
  final int bytes;
  final int totalBytes;

  /// 0–1 across the downloads.
  final double fraction;

  bool get isEmpty => total == 0;
  bool get isDone => total > 0 && done == total;
  bool get isActive => active > 0;

  /// Nothing moving, and something to resume or retry.
  bool get isStopped => active == 0 && (paused > 0 || failed > 0);

  @override
  bool operator ==(Object other) =>
      other is ParentProgress &&
      other.total == total &&
      other.done == done &&
      other.active == active &&
      other.paused == paused &&
      other.failed == failed &&
      other.bytes == bytes &&
      other.totalBytes == totalBytes &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(
    total,
    done,
    active,
    paused,
    failed,
    bytes,
    totalBytes,
    fraction,
  );
}
