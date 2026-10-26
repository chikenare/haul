import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/download_actions.dart';
import 'package:haul/src/widgets/haul_controller.dart';
import 'package:haul/src/widgets/haul_strings.dart';

/// Rebuilds with the download [id] on every change of it; null once it is
/// gone. The base of every widget here, and of an app's own.
class HaulRecordBuilder extends StatelessWidget {
  const HaulRecordBuilder({
    super.key,
    required this.controller,
    required this.id,
    required this.builder,
  });

  final HaulController controller;

  final String id;
  final Widget Function(BuildContext context, DownloadRecord? record) builder;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    return HaulEngineBuilder<DownloadRecord?>(
      identity: (engine, id),
      stream: () => engine.watch(id),
      current: () => engine.byId(id),
      builder: builder,
    );
  }
}

/// Follows one of the engine's streams, subscribed once per [identity]
/// rather than on every rebuild of the parent.
class HaulEngineBuilder<T> extends StatefulWidget {
  const HaulEngineBuilder({
    super.key,
    required this.identity,
    required this.stream,
    required this.current,
    required this.builder,
  });

  /// What the stream depends on; a new one subscribes again.
  final Object identity;
  final Stream<T> Function() stream;
  final T Function() current;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<HaulEngineBuilder<T>> createState() => _HaulEngineBuilderState<T>();
}

class _HaulEngineBuilderState<T> extends State<HaulEngineBuilder<T>> {
  late Stream<T> _stream = widget.stream();

  @override
  void didUpdateWidget(HaulEngineBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) _stream = widget.stream();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    // Another identity starts from its own value, not the last one's.
    key: ValueKey(widget.identity),
    stream: _stream,
    initialData: widget.current(),
    builder: (context, snapshot) => widget.builder(context, snapshot.data as T),
  );
}

/// A download's picture: [DownloadRecord.imageUrl] (a URL or a local
/// path), or the theme's placeholder.
class HaulThumbnail extends StatelessWidget {
  const HaulThumbnail({super.key, required this.imageUrl, this.size});

  final String? imageUrl;

  /// Null: `HaulTheme.thumbnailSize`.
  final Size? size;

  @override
  Widget build(BuildContext context) {
    final theme = HaulTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final size = this.size ?? theme.thumbnailSize;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(theme.placeholderIcon, color: scheme.onSurfaceVariant),
    );
    final url = imageUrl;
    final cacheWidth = (size.width * MediaQuery.devicePixelRatioOf(context))
        .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.thumbnailRadius),
      child: SizedBox.fromSize(
        size: size,
        child: url == null
            ? placeholder
            : url.startsWith('http')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => placeholder,
              )
            : Image.file(
                File(url),
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

String _label(HaulStrings strings, HaulAction action) => switch (action) {
  HaulAction.pause => strings.pause,
  HaulAction.resume => strings.resume,
  HaulAction.retry => strings.retry,
  HaulAction.play => strings.play,
  HaulAction.export => strings.export,
  HaulAction.removeKeepFile => strings.removeKeepFile,
  HaulAction.delete => strings.delete,
};

IconData _icon(HaulAction action) => switch (action) {
  HaulAction.pause => Icons.pause,
  HaulAction.resume => Icons.play_arrow,
  HaulAction.retry => Icons.refresh,
  HaulAction.play => Icons.play_circle_outline,
  HaulAction.export => Icons.save_alt,
  HaulAction.removeKeepFile => Icons.playlist_remove,
  HaulAction.delete => Icons.delete_outline,
};

/// Asks before deleting [record]; true when the user agreed.
Future<bool> confirmHaulDelete(
  BuildContext context,
  HaulController controller,
  String title,
) async {
  final strings = controller.stringsOf(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(strings.deleteConfirm(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.delete),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// An entry of the app's own in one of haul's menus — send to a TV,
/// share — shown after haul's actions and before the ones that remove.
@immutable
class HaulMenuItem {
  const HaulMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final String label;

  /// With the menu's button's context, still mounted once the menu closed.
  final FutureOr<void> Function(BuildContext context) onSelected;
}

/// The app's entries for one menu of [T] (a record, a parent), read each
/// time it opens: an entry may depend on its state.
typedef HaulMenuItems<T> =
    List<HaulMenuItem> Function(BuildContext context, T subject);

/// [items] as a popup menu's rows: haul's [leading], the app's [extra], then
/// haul's [trailing] — removing comes last.
List<PopupMenuEntry<Object>> _menuRows({
  required List<(Object, IconData, String)> leading,
  required List<HaulMenuItem> extra,
  required List<(Object, IconData, String)> trailing,
}) {
  PopupMenuItem<Object> row(Object value, IconData icon, String label) =>
      PopupMenuItem<Object>(
        value: value,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
        ),
      );
  return [
    for (final (value, icon, label) in leading) row(value, icon, label),
    for (final item in extra) row(item, item.icon, item.label),
    for (final (value, icon, label) in trailing) row(value, icon, label),
  ];
}

/// The menu of a download's row: every action [DownloadActions.menu]
/// allows, with the app's [menuItems] before the ones that remove. Delete
/// asks first.
class HaulActionsMenu extends StatelessWidget {
  const HaulActionsMenu({
    super.key,
    required this.controller,
    required this.record,
    this.onPlay,
    this.menuItems,
  });

  final HaulController controller;

  final DownloadRecord record;
  final void Function(DownloadRecord record)? onPlay;
  final HaulMenuItems<DownloadRecord>? menuItems;

  static const _removing = {HaulAction.removeKeepFile, HaulAction.delete};

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    final actions = DownloadActions.of(record, canRetry: controller.canRetry);
    (Object, IconData, String) entry(HaulAction action) =>
        (action, _icon(action), _label(strings, action));
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.more_vert),
      onSelected: (choice) async {
        // An export takes a while: its result is said even if the row is
        // gone by then.
        final messenger = ScaffoldMessenger.maybeOf(context);
        switch (choice) {
          case HaulMenuItem(:final onSelected):
            await onSelected(context);
          case HaulAction.delete:
            if (await confirmHaulDelete(context, controller, record.title)) {
              await runHaulAction(controller.engine, record, HaulAction.delete);
            }
          case HaulAction.export:
            final error = await runHaulAction(
              controller.engine,
              record,
              HaulAction.export,
            );
            messenger?.showSnackBar(
              SnackBar(
                content: Text(
                  error == null ? strings.exported : strings.error(error),
                ),
              ),
            );
          case final HaulAction action:
            await runHaulAction(
              controller.engine,
              record,
              action,
              play: onPlay,
            );
        }
      },
      itemBuilder: (menuContext) => _menuRows(
        leading: [
          for (final a in actions.menu)
            if (!_removing.contains(a)) entry(a),
        ],
        extra: menuItems?.call(context, record) ?? const [],
        trailing: [
          for (final a in actions.menu)
            if (_removing.contains(a)) entry(a),
        ],
      ),
    );
  }
}

/// One row of the downloads list: picture with its progress, title, a line
/// when there is something to say, and the actions in a menu. Every part
/// can be replaced.
class HaulDownloadTile extends StatelessWidget {
  const HaulDownloadTile({
    super.key,
    required this.controller,
    required this.id,
    this.onPlay,
    this.onTap,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.showMenu = true,
    this.menuItems,
  });

  final HaulController controller;

  final String id;

  /// Opens a finished download; also what tapping one does.
  final void Function(DownloadRecord record)? onPlay;

  /// Replaces what tapping does (by default: play when done).
  final void Function(DownloadRecord record)? onTap;

  final Widget Function(BuildContext context, DownloadRecord record)? leading;
  final Widget Function(BuildContext context, DownloadRecord record)? title;
  final Widget Function(BuildContext context, DownloadRecord record)? subtitle;
  final Widget Function(BuildContext context, DownloadRecord record)? trailing;
  final bool showMenu;

  /// The app's own entries in the menu (see [HaulActionsMenu]).
  final HaulMenuItems<DownloadRecord>? menuItems;

  @override
  Widget build(BuildContext context) {
    return HaulRecordBuilder(
      controller: controller,
      id: id,
      builder: (context, record) {
        if (record == null) return const SizedBox.shrink();
        final theme = HaulTheme.of(context);
        return InkWell(
          onTap: () {
            if (onTap case final onTap?) return onTap(record);
            if (record.status == DownloadStatus.done) onPlay?.call(record);
          },
          child: Padding(
            padding: theme.tilePadding,
            child: Row(
              children: [
                leading?.call(context, record) ??
                    _ProgressThumbnail(controller: controller, record: record),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title?.call(context, record) ??
                          Text(
                            record.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        subtitle!(context, record),
                      ] else
                        _Summary(controller: controller, record: record),
                    ],
                  ),
                ),
                ?trailing?.call(context, record),
                if (showMenu)
                  HaulActionsMenu(
                    controller: controller,
                    record: record,
                    onPlay: onPlay,
                    menuItems: menuItems,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressThumbnail extends StatelessWidget {
  const _ProgressThumbnail({required this.controller, required this.record});

  final HaulController controller;

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = HaulTheme.of(context);
    final fraction = record.progress.fraction;
    return Stack(
      children: [
        HaulThumbnail(
          imageUrl:
              controller.engine.imageOf(record) ?? record.parent?.imageUrl,
        ),
        // Not while it waits its turn or reads its source: the text says
        // so, and an endless bar there is only noise.
        if (record.status
            case DownloadStatus.downloading ||
                DownloadStatus.paused ||
                DownloadStatus.assembling ||
                DownloadStatus.failed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(theme.thumbnailRadius),
              ),
              child: LinearProgressIndicator(
                value: record.status == DownloadStatus.failed ? 0 : fraction,
                minHeight: 3,
                color: theme.progressOf(context),
                backgroundColor: Colors.black38,
              ),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.record});

  final HaulController controller;

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    final theme = Theme.of(context);
    final failed = record.status == DownloadStatus.failed;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: failed
          ? HaulTheme.of(context).errorOf(context)
          : theme.colorScheme.onSurfaceVariant,
    );
    return HaulEngineBuilder<bool>(
      identity: controller.engine,
      stream: controller.engine.watchWaitingForWifi,
      current: () => controller.engine.waitingForWifi,
      builder: (context, waiting) {
        final text = downloadSummary(record, strings, waitingForWifi: waiting);
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text,
            maxLines: failed ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
      },
    );
  }
}
