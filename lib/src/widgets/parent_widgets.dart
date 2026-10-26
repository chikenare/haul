import 'package:flutter/material.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/parents.dart';
import 'package:haul/src/widgets/download_widgets.dart';
import 'package:haul/src/widgets/haul_controller.dart';

/// Every download, a parent as one row with its children inside, newest
/// first. Rebuilt only when a download comes, goes or moves; each row
/// follows its own progress.
class HaulDownloadList extends StatelessWidget {
  const HaulDownloadList({
    super.key,
    required this.controller,
    this.onPlay,
    this.onOpenParent,
    this.itemBuilder,
    this.parentBuilder,
    this.empty,
    this.padding,
    this.menuItems,
  });

  final HaulController controller;

  final void Function(DownloadRecord record)? onPlay;

  /// The app's own entries in each default row's menu (see
  /// `HaulActionsMenu`).
  final HaulMenuItems<DownloadRecord>? menuItems;

  /// What tapping a parent does: usually a screen with [HaulParentView].
  final void Function(ParentDownloads parent)? onOpenParent;

  /// Replaces the row of a loose download (by default [HaulDownloadTile]).
  final Widget Function(BuildContext context, String id)? itemBuilder;

  /// Replaces the row of a parent (by default [HaulParentTile]).
  final Widget Function(BuildContext context, ParentDownloads parent)?
  parentBuilder;

  /// Shown when there is nothing; by default a line of text.
  final Widget? empty;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    return HaulEngineBuilder<List<DownloadEntry>>(
      identity: engine,
      stream: engine.watchEntries,
      current: () => engine.entries,
      builder: (context, entries) {
        if (entries.isEmpty) {
          return empty ??
              Center(child: Text(controller.stringsOf(context).empty));
        }
        return ListView.builder(
          padding: padding,
          itemCount: entries.length,
          itemBuilder: (context, i) => switch (entries[i]) {
            SingleDownload(:final id) =>
              itemBuilder?.call(context, id) ??
                  HaulDownloadTile(
                    key: ValueKey(id),
                    controller: controller,
                    id: id,
                    onPlay: onPlay,
                    menuItems: menuItems,
                  ),
            final ParentDownloads parent =>
              parentBuilder?.call(context, parent) ??
                  HaulParentTile(
                    key: ValueKey('parent:${parent.parent.id}'),
                    controller: controller,
                    parent: parent,
                    onTap: onOpenParent == null
                        ? null
                        : () => onOpenParent!(parent),
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
    required this.controller,
    required this.ids,
    required this.builder,
  });

  final HaulController controller;

  final List<String> ids;
  final Widget Function(BuildContext context, List<DownloadRecord> records)
  builder;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    List<DownloadRecord> read() => [for (final id in ids) ?engine.byId(id)];
    return HaulEngineBuilder<List<DownloadRecord>>(
      identity: (engine, Object.hashAll(ids)),
      stream: () => engine.watchAll().map((_) => read()),
      current: read,
      builder: builder,
    );
  }
}

/// The children of [parentId], now and on every change of any of them.
class HaulChildrenBuilder extends StatelessWidget {
  const HaulChildrenBuilder({
    super.key,
    required this.controller,
    required this.parentId,
    required this.builder,
  });

  final HaulController controller;

  final String parentId;
  final Widget Function(BuildContext context, List<DownloadRecord> children)
  builder;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    return HaulEngineBuilder<List<DownloadRecord>>(
      identity: (engine, parentId),
      stream: () => engine.watchChildren(parentId),
      current: () => engine.childrenOf(parentId),
      builder: builder,
    );
  }
}

/// How far the children of [parentId] are — those that pass [where], when
/// given (one season: `where: (r) => r.metadata['season'] == 2`).
class HaulParentProgressBuilder extends StatelessWidget {
  const HaulParentProgressBuilder({
    super.key,
    required this.controller,
    required this.parentId,
    this.where,
    required this.builder,
  });

  final HaulController controller;

  final String parentId;
  final bool Function(DownloadRecord record)? where;
  final Widget Function(BuildContext context, ParentProgress progress) builder;

  @override
  Widget build(BuildContext context) => HaulChildrenBuilder(
    controller: controller,
    parentId: parentId,
    builder: (context, children) => builder(
      context,
      ParentProgress.of(where == null ? children : children.where(where!)),
    ),
  );
}

/// A parent's state at a glance, like [HaulProgressIcon] for one download:
/// a ring across its children, a pause, a check, an alert.
class HaulParentProgressIcon extends StatelessWidget {
  const HaulParentProgressIcon({
    super.key,
    required this.progress,
    this.size = 24,
  });

  final ParentProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = HaulTheme.of(context);
    final color = theme.progressOf(context);
    final Widget child;
    if (progress.isDone) {
      child = Icon(Icons.download_done, size: size);
    } else if (progress.isActive || progress.isStopped) {
      child = Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size * 0.85,
            child: CircularProgressIndicator(
              value: progress.fraction,
              strokeWidth: 2.5,
              color: progress.isStopped && progress.failed > 0
                  ? theme.errorOf(context)
                  : color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
          if (progress.isStopped)
            Icon(
              progress.failed > 0 ? Icons.priority_high : Icons.pause,
              size: size * 0.5,
            ),
        ],
      );
    } else {
      // Nothing yet, or some done and the rest never asked for.
      child = Icon(Icons.download_outlined, size: size);
    }
    return SizedBox.square(
      dimension: size,
      child: Center(child: child),
    );
  }
}

/// The download button of a show — or of a season, with [where]:
/// [onDownload] while nothing moves and nothing waits — the app enqueues
/// what is missing its own way, and what is there already is left alone —
/// then pause all while they move, and resume (or retry) all once they
/// stopped.
class HaulParentDownloadButton extends StatelessWidget {
  const HaulParentDownloadButton({
    super.key,
    required this.controller,
    required this.parentId,
    this.where,
    required this.onDownload,
    this.builder,
  });

  final HaulController controller;

  final String parentId;
  final bool Function(DownloadRecord record)? where;
  final Future<void> Function() onDownload;

  /// To draw it differently; [onPressed] does what the default would.
  final Widget Function(
    BuildContext context,
    ParentProgress progress,
    VoidCallback onPressed,
  )?
  builder;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final strings = controller.stringsOf(context);
    return HaulParentProgressBuilder(
      controller: controller,
      parentId: parentId,
      where: where,
      builder: (context, progress) {
        final (VoidCallback onPressed, String tooltip) = progress.isActive
            ? (
                () => engine.pauseParent(parentId, where: where),
                strings.pauseAll,
              )
            : progress.isStopped
            ? (
                () => engine.resumeParent(parentId, where: where),
                strings.resumeAll,
              )
            : (() => onDownload(), strings.download);
        if (builder case final builder?) {
          return builder(context, progress, onPressed);
        }
        return IconButton(
          tooltip: progress.isEmpty
              ? tooltip
              : '$tooltip · ${strings.doneOf(progress.done, progress.total)}',
          onPressed: onPressed,
          icon: HaulParentProgressIcon(progress: progress),
        );
      },
    );
  }
}

/// A parent's row: its picture, its title, how many children it holds and
/// how far along they are.
class HaulParentTile extends StatelessWidget {
  const HaulParentTile({
    super.key,
    required this.controller,
    required this.parent,
    this.onTap,
  });

  final HaulController controller;

  final ParentDownloads parent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final strings = controller.stringsOf(context);
    final theme = HaulTheme.of(context);
    final text = Theme.of(context).textTheme;
    return HaulParentProgressBuilder(
      controller: controller,
      parentId: parent.parent.id,
      builder: (context, progress) {
        final image =
            parent.parent.imageUrl ??
            parent.ids
                .map(engine.byId)
                .nonNulls
                .map(engine.imageOf)
                .nonNulls
                .firstOrNull;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: theme.tilePadding,
            child: Row(
              children: [
                HaulThumbnail(imageUrl: image),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parent.parent.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (progress.isDone)
                            strings.downloads(progress.total)
                          else
                            strings.doneOf(progress.done, progress.total),
                          if (progress.totalBytes > 0)
                            strings.bytes(progress.totalBytes),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!progress.isDone) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 3,
                          color: progress.isStopped && progress.failed > 0
                              ? theme.errorOf(context)
                              : theme.progressOf(context),
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

/// The children of one parent. Headings and order are the app's, read
/// from what it keeps in each child (`metadata`): [sectionOf] gives the
/// heading a child goes under (`Season 1`; null: none), and [sort] their
/// order — by title in natural order otherwise. A heading is drawn where
/// it changes, so sort by it first. [onEmpty] runs once the parent has no
/// children left (pop the screen).
class HaulParentView extends StatelessWidget {
  const HaulParentView({
    super.key,
    required this.controller,
    required this.parentId,
    this.onPlay,
    this.sectionOf,
    this.sort,
    this.itemBuilder,
    this.sectionBuilder,
    this.onEmpty,
    this.padding,
    this.menuItems,
  });

  final HaulController controller;

  final String parentId;
  final void Function(DownloadRecord record)? onPlay;

  /// The app's own entries in each default row's menu (see
  /// `HaulActionsMenu`).
  final HaulMenuItems<DownloadRecord>? menuItems;
  final String? Function(DownloadRecord record)? sectionOf;
  final Comparator<DownloadRecord>? sort;
  final Widget Function(BuildContext context, String id)? itemBuilder;

  /// Replaces a heading; by default a line of text.
  final Widget Function(BuildContext context, String section)? sectionBuilder;
  final VoidCallback? onEmpty;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final strings = controller.stringsOf(context);
    return HaulEngineBuilder<ParentDownloads?>(
      identity: (engine, parentId),
      stream: () => engine.watchParent(parentId),
      current: () => engine.parent(parentId),
      builder: (context, parent) {
        if (parent == null) {
          return _EmptyOnce(
            onEmpty: onEmpty,
            child: Center(child: Text(strings.empty)),
          );
        }
        final children = parent.ids.map(engine.byId).nonNulls.toList();
        if (sort case final sort?) children.sort(sort);
        final rows = <Widget>[];
        String? current;
        for (final (i, child) in children.indexed) {
          final section = sectionOf?.call(child);
          if (section != null && (i == 0 || section != current)) {
            rows.add(
              sectionBuilder?.call(context, section) ??
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      section,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
            );
          }
          current = section;
          rows.add(
            itemBuilder?.call(context, child.id) ??
                HaulDownloadTile(
                  key: ValueKey(child.id),
                  controller: controller,
                  id: child.id,
                  onPlay: onPlay,
                  menuItems: menuItems,
                ),
          );
        }
        return ListView(padding: padding, children: rows);
      },
    );
  }
}

/// A parent's own actions, for an app bar: pause all, resume all, the
/// app's [menuItems], delete all (asked first).
class HaulParentActions extends StatelessWidget {
  const HaulParentActions({
    super.key,
    required this.controller,
    required this.parent,
    this.menuItems,
  });

  final HaulController controller;

  final DownloadParent parent;
  final HaulMenuItems<DownloadParent>? menuItems;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final strings = controller.stringsOf(context);
    return PopupMenuButton<Object>(
      onSelected: (choice) async {
        switch (choice) {
          case HaulMenuItem(:final onSelected):
            await onSelected(context);
          case _ParentAction.pause:
            await engine.pauseParent(parent.id);
          case _ParentAction.resume:
            await engine.resumeParent(parent.id);
          case _ParentAction.delete:
            final count = engine.childrenOf(parent.id).length;
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(strings.deleteParentConfirm(parent.title, count)),
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
            if (yes ?? false) await engine.deleteParent(parent.id);
        }
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem(
          value: _ParentAction.pause,
          child: Text(strings.pauseAll),
        ),
        PopupMenuItem(
          value: _ParentAction.resume,
          child: Text(strings.resumeAll),
        ),
        for (final item in menuItems?.call(context, parent) ?? const [])
          PopupMenuItem(value: item, child: Text(item.label)),
        PopupMenuItem(
          value: _ParentAction.delete,
          child: Text(strings.deleteAll),
        ),
      ],
    );
  }
}

enum _ParentAction { pause, resume, delete }

/// [child], running [onEmpty] once after it first shows — not on every
/// rebuild while it stays: a second `pop` would close the screen below.
class _EmptyOnce extends StatefulWidget {
  const _EmptyOnce({required this.onEmpty, required this.child});

  final VoidCallback? onEmpty;
  final Widget child;

  @override
  State<_EmptyOnce> createState() => _EmptyOnceState();
}

class _EmptyOnceState extends State<_EmptyOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEmpty?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
