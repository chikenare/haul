import 'dart:io';

import 'package:flutter/material.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/download_actions.dart';
import 'package:haul/src/widgets/haul_scope.dart';
import 'package:haul/src/widgets/haul_strings.dart';

/// Rebuilds with the download [id] on every change of it; null once it is
/// gone. The base of every widget here, and of an app's own.
class HaulRecordBuilder extends StatelessWidget {
  const HaulRecordBuilder({super.key, required this.id, required this.builder});

  final String id;
  final Widget Function(BuildContext context, DownloadRecord? record) builder;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    return HaulEngineBuilder<DownloadRecord?>(
      identity: (engine, id),
      stream: () => engine.watch(id),
      current: () => engine.byId(id),
      builder: builder,
    );
  }
}

/// [HaulRecordBuilder] by the app's key: what a title's page shows before
/// and after it is asked for.
class HaulKeyBuilder extends StatelessWidget {
  const HaulKeyBuilder({
    super.key,
    required this.downloadKey,
    required this.builder,
  });

  final String downloadKey;
  final Widget Function(BuildContext context, DownloadRecord? record) builder;

  @override
  Widget build(BuildContext context) {
    final engine = HaulScope.of(context).engine;
    return HaulEngineBuilder<DownloadRecord?>(
      identity: (engine, downloadKey),
      stream: () =>
          engine.watchAll().map((_) => engine.byKey(downloadKey)).distinct(),
      current: () => engine.byKey(downloadKey),
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

/// A download's state at a glance: a ring filling up, a pause, a check,
/// an alert.
class HaulProgressIcon extends StatelessWidget {
  const HaulProgressIcon({super.key, required this.record, this.size = 24});

  final DownloadRecord? record;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = HaulTheme.of(context);
    final record = this.record;
    final Widget child = switch (record?.status) {
      null => Icon(Icons.download_outlined, size: size),
      DownloadStatus.done => Icon(Icons.download_done, size: size),
      DownloadStatus.failed => Icon(
        Icons.error_outline,
        size: size,
        color: theme.errorOf(context),
      ),
      DownloadStatus.paused => Stack(
        alignment: Alignment.center,
        children: [
          _Ring(
            value: record!.progress.fraction ?? 0,
            size: size,
            color: theme.progressOf(context),
          ),
          Icon(Icons.pause, size: size * 0.55),
        ],
      ),
      _ => _Ring(
        value: record!.status == DownloadStatus.downloading
            ? record.progress.fraction
            : null,
        size: size,
        color: theme.progressOf(context),
      ),
    };
    return SizedBox.square(
      dimension: size,
      child: Center(child: child),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.size, required this.color});

  final double? value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size * 0.85,
    child: CircularProgressIndicator(
      value: value,
      strokeWidth: 2.5,
      color: color,
      backgroundColor: color.withValues(alpha: 0.2),
    ),
  );
}

/// The download button of a title: [onDownload] when it was never asked
/// for — the app enqueues it its own way — and then pause, resume, retry
/// or [onPlay] as it goes.
class HaulDownloadButton extends StatelessWidget {
  const HaulDownloadButton({
    super.key,
    required this.downloadKey,
    required this.onDownload,
    this.onPlay,
    this.builder,
  });

  final String downloadKey;
  final Future<void> Function() onDownload;
  final void Function(DownloadRecord record)? onPlay;

  /// To draw it differently; [onPressed] does what the default would.
  final Widget Function(
    BuildContext context,
    DownloadRecord? record,
    VoidCallback? onPressed,
  )?
  builder;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final strings = HaulScope.stringsOf(context);
    return HaulKeyBuilder(
      downloadKey: downloadKey,
      builder: (context, record) {
        final action = record == null
            ? null
            : DownloadActions.of(record, canRetry: scope.canRetry).primary;
        final VoidCallback? onPressed = record == null
            ? () => onDownload()
            : action == null
            ? null
            : () => runHaulAction(scope.engine, record, action, play: onPlay);
        if (builder case final builder?) {
          return builder(context, record, onPressed);
        }
        return IconButton(
          tooltip: record == null
              ? strings.download
              : action == null
              ? strings.status(record.status)
              : _label(strings, action),
          onPressed: onPressed,
          icon: HaulProgressIcon(record: record),
        );
      },
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
Future<bool> confirmHaulDelete(BuildContext context, String title) async {
  final strings = HaulScope.stringsOf(context);
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

/// The menu of a download's row: every action [DownloadActions.menu]
/// allows. Delete asks first.
class HaulActionsMenu extends StatelessWidget {
  const HaulActionsMenu({super.key, required this.record, this.onPlay});

  final DownloadRecord record;
  final void Function(DownloadRecord record)? onPlay;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final strings = HaulScope.stringsOf(context);
    final actions = DownloadActions.of(record, canRetry: scope.canRetry);
    return PopupMenuButton<HaulAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) async {
        if (action == HaulAction.delete &&
            !await confirmHaulDelete(context, record.title)) {
          return;
        }
        await runHaulAction(scope.engine, record, action, play: onPlay);
      },
      itemBuilder: (context) => [
        for (final action in actions.menu)
          PopupMenuItem(
            value: action,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(action)),
              title: Text(_label(strings, action)),
            ),
          ),
      ],
    );
  }
}

/// One row of the downloads list: picture, title, state and the main
/// action at hand, with the rest in a menu. Every part can be replaced.
class HaulDownloadTile extends StatelessWidget {
  const HaulDownloadTile({
    super.key,
    required this.id,
    this.onPlay,
    this.onTap,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.showMenu = true,
  });

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

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    return HaulRecordBuilder(
      id: id,
      builder: (context, record) {
        if (record == null) return const SizedBox.shrink();
        final theme = HaulTheme.of(context);
        final actions = DownloadActions.of(record, canRetry: scope.canRetry);
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
                    _ProgressThumbnail(record: record),
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
                      const SizedBox(height: 4),
                      subtitle?.call(context, record) ??
                          _Summary(record: record),
                    ],
                  ),
                ),
                trailing?.call(context, record) ??
                    _PrimaryButton(
                      record: record,
                      actions: actions,
                      onPlay: onPlay,
                    ),
                if (showMenu) HaulActionsMenu(record: record, onPlay: onPlay),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressThumbnail extends StatelessWidget {
  const _ProgressThumbnail({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = HaulTheme.of(context);
    final fraction = record.progress.fraction;
    return Stack(
      children: [
        HaulThumbnail(
          imageUrl:
              HaulScope.of(context).engine.imageOf(record) ??
              record.parent?.imageUrl,
        ),
        if (record.status != DownloadStatus.done)
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
  const _Summary({required this.record});

  final DownloadRecord record;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final strings = HaulScope.stringsOf(context);
    final theme = Theme.of(context);
    final failed = record.status == DownloadStatus.failed;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: failed
          ? HaulTheme.of(context).errorOf(context)
          : theme.colorScheme.onSurfaceVariant,
    );
    return HaulEngineBuilder<bool>(
      identity: scope.engine,
      stream: scope.engine.watchWaitingForWifi,
      current: () => scope.engine.waitingForWifi,
      builder: (context, waiting) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            downloadSummary(record, strings, waitingForWifi: waiting),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          if (failed && record.error != null)
            Text(
              strings.error(record.error!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.record,
    required this.actions,
    required this.onPlay,
  });

  final DownloadRecord record;
  final DownloadActions actions;
  final void Function(DownloadRecord record)? onPlay;

  @override
  Widget build(BuildContext context) {
    final action = actions.primary;
    if (action == null) {
      return record.status == DownloadStatus.assembling
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const SizedBox.shrink();
    }
    final engine = HaulScope.of(context).engine;
    return IconButton(
      tooltip: _label(HaulScope.stringsOf(context), action),
      icon: Icon(_icon(action)),
      onPressed: () => runHaulAction(engine, record, action, play: onPlay),
    );
  }
}
