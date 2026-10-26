import 'package:flutter/material.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/engine/parents.dart';
import 'package:haul/src/widgets/download_actions.dart';
import 'package:haul/src/widgets/download_widgets.dart';
import 'package:haul/src/widgets/haul_controller.dart';

/// Every download, newest first: a loose one as its own row, and a parent
/// (a show) as one row that opens right there into its children. Rebuilt
/// only when a download comes, goes or moves; each row follows its own
/// progress.
///
/// The children's headings and order are the app's, read from what it
/// keeps in each (`metadata`): [sectionOf] gives the heading a child goes
/// under (`Season 1`; null: none), and [sort] their order — by title in
/// natural order otherwise. A heading is drawn where it changes, so sort by
/// it first.
class HaulDownloadList extends StatefulWidget {
  const HaulDownloadList({
    super.key,
    required this.controller,
    this.onPlay,
    this.menuItems,
    this.parentMenuItems,
    this.sectionOf,
    this.sort,
    this.itemBuilder,
    this.sectionBuilder,
    this.empty,
    this.padding,
  });

  final HaulController controller;

  final void Function(DownloadRecord record)? onPlay;

  /// The app's own entries in each download's menu, after haul's actions
  /// and before the ones that remove.
  final HaulMenuItems<DownloadRecord>? menuItems;

  /// The same in a parent's menu (pause all, resume all, delete all).
  final HaulMenuItems<DownloadParent>? parentMenuItems;

  final String? Function(DownloadRecord record)? sectionOf;
  final Comparator<DownloadRecord>? sort;

  /// Replaces the row of a download, loose or a child.
  final Widget Function(BuildContext context, String id)? itemBuilder;

  /// Replaces a heading among a parent's children; by default a line of
  /// text.
  final Widget Function(BuildContext context, String section)? sectionBuilder;

  /// Shown when there is nothing; by default a line of text.
  final Widget? empty;
  final EdgeInsets? padding;

  @override
  State<HaulDownloadList> createState() => _HaulDownloadListState();
}

class _HaulDownloadListState extends State<HaulDownloadList> {
  /// The parents open now, by id.
  final _open = <String>{};

  HaulController get _controller => widget.controller;

  Widget _item(BuildContext context, String id) =>
      widget.itemBuilder?.call(context, id) ??
      HaulDownloadTile(
        key: ValueKey(id),
        controller: _controller,
        id: id,
        onPlay: widget.onPlay,
        menuItems: widget.menuItems,
      );

  /// A parent's children as rows, under their headings.
  List<Widget> _children(BuildContext context, ParentDownloads parent) {
    final engine = _controller.engine;
    final children = parent.ids.map(engine.byId).nonNulls.toList();
    if (widget.sort case final sort?) children.sort(sort);
    final rows = <Widget>[];
    String? current;
    for (final (i, child) in children.indexed) {
      final section = widget.sectionOf?.call(child);
      if (section != null && (i == 0 || section != current)) {
        rows.add(
          widget.sectionBuilder?.call(context, section) ??
              Padding(
                key: ValueKey('section:${parent.parent.id}:$section'),
                padding: const EdgeInsets.fromLTRB(32, 12, 16, 4),
                child: Text(
                  section,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
        );
      }
      current = section;
      rows.add(
        Padding(
          key: ValueKey('child:${child.id}'),
          padding: const EdgeInsets.only(left: 16),
          child: _item(context, child.id),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final engine = _controller.engine;
    return HaulEngineBuilder<List<DownloadEntry>>(
      identity: engine,
      stream: engine.watchEntries,
      current: () => engine.entries,
      builder: (context, entries) {
        // A parent that is gone forgets it was open, so it comes back
        // closed. No setState: this is already a build.
        _open.retainWhere(
          (id) => entries.any((e) => e is ParentDownloads && e.parent.id == id),
        );
        if (entries.isEmpty) {
          return widget.empty ??
              Center(child: Text(_controller.stringsOf(context).empty));
        }
        final rows = <Widget>[
          for (final entry in entries)
            ...switch (entry) {
              SingleDownload(:final id) => [_item(context, id)],
              final ParentDownloads parent => [
                HaulParentTile(
                  key: ValueKey('parent:${parent.parent.id}'),
                  controller: _controller,
                  parent: parent,
                  open: _open.contains(parent.parent.id),
                  menuItems: widget.parentMenuItems,
                  onTap: () => setState(() {
                    if (!_open.remove(parent.parent.id)) {
                      _open.add(parent.parent.id);
                    }
                  }),
                ),
                if (_open.contains(parent.parent.id))
                  ..._children(context, parent),
              ],
            },
        ];
        return ListView.builder(
          padding: widget.padding,
          itemCount: rows.length,
          itemBuilder: (context, i) => rows[i],
        );
      },
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

/// A parent's row: its picture, its title, how many children it holds and
/// how far along they are, its menu, and whether it is [open].
class HaulParentTile extends StatelessWidget {
  const HaulParentTile({
    super.key,
    required this.controller,
    required this.parent,
    this.open = false,
    this.menuItems,
    this.onTap,
  });

  final HaulController controller;

  final ParentDownloads parent;
  final bool open;
  final HaulMenuItems<DownloadParent>? menuItems;
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
                _ParentMenu(
                  controller: controller,
                  parent: parent.parent,
                  menuItems: menuItems,
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A parent's own actions: pause all, resume all, the app's [menuItems],
/// delete all (asked first).
class _ParentMenu extends StatelessWidget {
  const _ParentMenu({
    required this.controller,
    required this.parent,
    this.menuItems,
  });

  final HaulController controller;

  final DownloadParent parent;
  final HaulMenuItems<DownloadParent>? menuItems;

  /// What a download's own menu would offer: pause, or resume and retry.
  HaulAction? _primary(DownloadRecord record) =>
      DownloadActions.of(record, canRetry: controller.canRetry).primary;

  bool _pausable(DownloadRecord record) => _primary(record) == HaulAction.pause;

  bool _resumable(DownloadRecord record) => switch (_primary(record)) {
    HaulAction.resume || HaulAction.retry => true,
    _ => false,
  };

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
            await engine.pauseParent(parent.id, where: _pausable);
          case _ParentAction.resume:
            await engine.resumeParent(parent.id, where: _resumable);
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
        // Only what some child allows: a finished series offers neither.
        if (engine.childrenOf(parent.id).any(_pausable))
          PopupMenuItem(
            value: _ParentAction.pause,
            child: Text(strings.pauseAll),
          ),
        if (engine.childrenOf(parent.id).any(_resumable))
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
