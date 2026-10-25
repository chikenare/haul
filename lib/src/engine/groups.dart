import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/model.dart';

/// One line of a downloads list: a download on its own, or a group of them.
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

final class GroupedDownloads extends DownloadEntry {
  const GroupedDownloads(this.group, this.sections);

  final DownloadGroup group;

  /// In their natural order; a group without sections has one, with a
  /// null [DownloadSection.id].
  final List<DownloadSection> sections;

  @override
  List<String> get ids => [for (final s in sections) ...s.ids];

  @override
  bool operator ==(Object other) =>
      other is GroupedDownloads &&
      other.group == group &&
      const ListEquality<DownloadSection>().equals(other.sections, sections);

  @override
  int get hashCode =>
      Object.hash(group, const ListEquality<DownloadSection>().hash(sections));
}

/// The downloads of one section of a group, in their order.
@immutable
class DownloadSection {
  const DownloadSection(this.id, this.ids);

  /// [DownloadRecord.section]; null for the ones without.
  final String? id;
  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is DownloadSection &&
      other.id == id &&
      const ListEquality<String>().equals(other.ids, ids);

  @override
  int get hashCode => Object.hash(id, const ListEquality<String>().hash(ids));
}

/// [records] as a list: groups and loose downloads together, newest first
/// (a group counts by its newest download). Within a group, sections in
/// their natural order — numbers as numbers, the ones without first — and
/// downloads by [DownloadRecord.order], then by when they were asked for.
List<DownloadEntry> downloadEntries(Iterable<DownloadRecord> records) {
  final loose = <DownloadRecord>[];
  final groups = <String, List<DownloadRecord>>{};
  for (final r in records) {
    final group = r.group;
    if (group == null) {
      loose.add(r);
    } else {
      (groups[group.id] ??= []).add(r);
    }
  }

  final entries = <(DateTime, DownloadEntry)>[
    for (final r in loose) (r.createdAt, SingleDownload(r.id)),
    for (final members in groups.values) _grouped(members),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final e in entries) e.$2];
}

(DateTime, DownloadEntry) _grouped(List<DownloadRecord> members) {
  final newest = members.reduce(
    (a, b) => b.createdAt.isAfter(a.createdAt) ? b : a,
  );
  final bySection = groupBy(members, (r) => r.section);
  final sections = [
    for (final id in bySection.keys.sorted(compareSections))
      DownloadSection(id, [
        for (final r in bySection[id]!.sorted(_byOrder)) r.id,
      ]),
  ];
  return (newest.createdAt, GroupedDownloads(newest.group!, sections));
}

int _byOrder(DownloadRecord a, DownloadRecord b) {
  final ao = a.order, bo = b.order;
  if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
  if (ao != null && bo == null) return -1;
  if (ao == null && bo != null) return 1;
  return a.createdAt.compareTo(b.createdAt);
}

/// Sections in their natural order: null first, numbers as numbers and
/// before words, words alphabetically.
@visibleForTesting
int compareSections(String? a, String? b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  final an = num.tryParse(a), bn = num.tryParse(b);
  if (an != null && bn != null) return an.compareTo(bn);
  if (an != null) return -1;
  if (bn != null) return 1;
  return compareNatural(a, b);
}
