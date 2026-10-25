import 'package:flutter/material.dart';
import 'package:haul/src/engine/groups.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/download_widgets.dart';
import 'package:haul/src/widgets/haul_scope.dart';

/// Every download, groups as one row each, newest first. Rebuilt only when
/// a download comes, goes or moves; each row follows its own progress.
class HaulDownloadList extends StatelessWidget {
  const HaulDownloadList({
    super.key,
    this.onPlay,
    this.onOpenGroup,
    this.itemBuilder,
    this.groupBuilder,
    this.empty,
    this.padding,
  });

  final void Function(DownloadRecord record)? onPlay;

  /// What tapping a group does: usually a screen with [HaulGroupView].
  final void Function(GroupedDownloads group)? onOpenGroup;

  /// Replaces the row of a loose download (by default [HaulDownloadTile]).
  final Widget Function(BuildContext context, String id)? itemBuilder;

  /// Replaces the row of a group (by default [HaulGroupTile]).
  final Widget Function(BuildContext context, GroupedDownloads group)?
  groupBuilder;

  /// Shown when there is nothing; by default a line of text.
  final Widget? empty;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    return HaulEngineBuilder<List<DownloadEntry>>(
      identity: engine,
      stream: engine.watchEntries,
      current: () => engine.entries,
      builder: (context, entries) {
        if (entries.isEmpty) {
          return empty ??
              Center(child: Text(HaulScope.stringsOf(context).empty));
        }
        return ListView.builder(
          padding: padding,
          itemCount: entries.length,
          itemBuilder: (context, i) => switch (entries[i]) {
            SingleDownload(:final id) =>
              itemBuilder?.call(context, id) ??
                  HaulDownloadTile(key: ValueKey(id), id: id, onPlay: onPlay),
            final GroupedDownloads group =>
              groupBuilder?.call(context, group) ??
                  HaulGroupTile(
                    key: ValueKey('group:${group.group.id}'),
                    group: group,
                    onTap: onOpenGroup == null
                        ? null
                        : () => onOpenGroup!(group),
                  ),
          },
        );
      },
    );
  }
}

/// The records of [ids], now and on every change of any of them.
class HaulRecordsBuilder extends StatelessWidget {
  const HaulRecordsBuilder({
    super.key,
    required this.ids,
    required this.builder,
  });

  final List<String> ids;
  final Widget Function(BuildContext context, List<DownloadRecord> records)
  builder;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    List<DownloadRecord> read() => [for (final id in ids) ?engine.byId(id)];
    return HaulEngineBuilder<List<DownloadRecord>>(
      identity: (engine, Object.hashAll(ids)),
      stream: () => engine.watchAll().map((_) => read()),
      current: read,
      builder: builder,
    );
  }
}

/// A group's row: its picture, its title, how many downloads it holds and
/// how far along they are.
class HaulGroupTile extends StatelessWidget {
  const HaulGroupTile({super.key, required this.group, this.onTap});

  final GroupedDownloads group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = HaulScope.stringsOf(context);
    final theme = HaulTheme.of(context);
    final text = Theme.of(context).textTheme;
    return HaulRecordsBuilder(
      ids: group.ids,
      builder: (context, records) {
        final active = records.where((r) => r.status != DownloadStatus.done);
        final total = records.fold<int>(
          0,
          (sum, r) => sum + r.progress.totalBytes,
        );
        final done = records.where((r) => r.status == DownloadStatus.done);
        final fraction = records.isEmpty ? null : done.length / records.length;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: theme.tilePadding,
            child: Row(
              children: [
                HaulThumbnail(
                  imageUrl:
                      group.group.imageUrl ??
                      records.map((r) => r.imageUrl).nonNulls.firstOrNull,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.group.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          strings.downloads(records.length),
                          if (total > 0) strings.bytes(total),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (active.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          color: theme.progressOf(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The downloads of one group, section by section, with its own actions
/// (pause, resume, delete all) for an app bar. Pops [onEmpty] — or does
/// nothing — once the group has no downloads left.
class HaulGroupView extends StatelessWidget {
  const HaulGroupView({
    super.key,
    required this.groupId,
    this.onPlay,
    this.itemBuilder,
    this.sectionBuilder,
    this.onEmpty,
    this.padding,
  });

  final String groupId;
  final void Function(DownloadRecord record)? onPlay;
  final Widget Function(BuildContext context, String id)? itemBuilder;

  /// Replaces a section's heading; by default `HaulStrings.section`.
  final Widget Function(BuildContext context, String section)? sectionBuilder;
  final VoidCallback? onEmpty;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    final strings = HaulScope.stringsOf(context);
    return HaulEngineBuilder<GroupedDownloads?>(
      identity: (engine, groupId),
      stream: () => engine.watchGroup(groupId),
      current: () => engine.group(groupId),
      builder: (context, group) {
        if (group == null) {
          if (onEmpty case final onEmpty?) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onEmpty());
          }
          return Center(child: Text(strings.empty));
        }
        final rows = <Widget>[
          for (final section in group.sections) ...[
            if (section.id case final id?)
              sectionBuilder?.call(context, id) ??
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      strings.section(id),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
            for (final id in section.ids)
              itemBuilder?.call(context, id) ??
                  HaulDownloadTile(key: ValueKey(id), id: id, onPlay: onPlay),
          ],
        ];
        return ListView(padding: padding, children: rows);
      },
    );
  }
}

/// The group's own actions, for an app bar: pause all, resume all,
/// delete all (asked first).
class HaulGroupActions extends StatelessWidget {
  const HaulGroupActions({super.key, required this.group});

  final DownloadGroup group;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    final strings = HaulScope.stringsOf(context);
    return PopupMenuButton<int>(
      onSelected: (choice) async {
        switch (choice) {
          case 0:
            await engine.pauseGroup(group.id);
          case 1:
            await engine.resumeGroup(group.id);
          case 2:
            final count = engine.group(group.id)?.ids.length ?? 0;
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(strings.deleteGroupConfirm(group.title, count)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(strings.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(strings.deleteAll),
                  ),
                ],
              ),
            );
            if (yes ?? false) await engine.deleteGroup(group.id);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 0, child: Text(strings.pauseAll)),
        PopupMenuItem(value: 1, child: Text(strings.resumeAll)),
        PopupMenuItem(value: 2, child: Text(strings.deleteAll)),
      ],
    );
  }
}
