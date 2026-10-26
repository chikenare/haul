import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/haul_output_sink.dart';
import 'package:haul/src/widgets/haul_controller.dart';
import 'package:haul/src/widgets/haul_settings.dart';

bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Whether the destination can be chosen here: Android, and desktop. iOS
/// keeps files in the app.
bool haulDestinationChoosable(HaulController controller) =>
    controller.android.isAndroid || _desktop;

/// Asks the platform for a folder: SAF on Android, the app's
/// `HaulController.pickDirectory` on desktop. Null when the user backs out or
/// there is no way to pick one.
Future<HaulFolder?> pickHaulFolder(
  HaulController controller, {
  HaulDestination? current,
}) async {
  if (controller.android.isAndroid) {
    try {
      return await controller.android.pickFolder(
        initialUri: switch (current) {
          FolderDestination(:final folder) => folder.uri,
          _ => null,
        },
      );
    } on Exception {
      return null;
    }
  }
  final path = await controller.pickDirectory?.call();
  return path == null ? null : HaulFolder(uri: path, name: path);
}

/// Follows [HaulController.settings]; [builder] gets them to [edit].
class _SettingsBuilder extends StatelessWidget {
  const _SettingsBuilder({required this.controller, required this.builder});

  final HaulController controller;
  final Widget Function(
    BuildContext context,
    HaulSettingsController edit,
    HaulSettings settings,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    final edit = controller.requireSettings;
    return ValueListenableBuilder<HaulSettings>(
      valueListenable: edit,
      builder: (context, settings, _) => builder(context, edit, settings),
    );
  }
}

/// The choice of format as two radio rows, for a sheet or a page.
class HaulFormatChoice extends StatelessWidget {
  const HaulFormatChoice({
    super.key,
    required this.controller,
    required this.merge,
    required this.onChanged,
  });

  final HaulController controller;
  final bool merge;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    return RadioGroup<bool>(
      groupValue: merge,
      onChanged: (value) => onChanged(value ?? false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<bool>(
            value: false,
            title: Text(strings.formatApp),
            subtitle: Text(strings.formatAppHint),
          ),
          RadioListTile<bool>(
            value: true,
            title: Text(strings.formatFile),
            subtitle: Text(strings.formatFileHint),
          ),
        ],
      ),
    );
  }
}

/// The choice of destination as radio rows: public, only in the app, or a
/// folder of the user's — which is picked when chosen, and kept as it was
/// when the user backs out of the picker.
class HaulDestinationChoice extends StatelessWidget {
  const HaulDestinationChoice({
    super.key,
    required this.controller,
    required this.destination,
    required this.onChanged,
  });

  final HaulController controller;
  final HaulDestination destination;
  final ValueChanged<HaulDestination> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    final canPick =
        controller.android.isAndroid || controller.pickDirectory != null;
    final folder = switch (destination) {
      FolderDestination(:final folder) => folder,
      _ => null,
    };

    Future<void> pick() async {
      final picked = await pickHaulFolder(controller, current: destination);
      if (picked != null) onChanged(HaulDestination.folder(picked));
    }

    return RadioGroup<String>(
      groupValue: destination.toJson()['type']! as String,
      onChanged: (type) async {
        switch (type) {
          case 'public':
            onChanged(const HaulDestination.public());
          case 'app':
            onChanged(const HaulDestination.app());
          case 'folder':
            await pick();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            value: 'public',
            title: Text(strings.destinationPublic),
            subtitle: Text(strings.destinationPublicHint),
          ),
          RadioListTile<String>(
            value: 'app',
            title: Text(strings.destinationApp),
            subtitle: Text(strings.destinationAppHint),
          ),
          if (canPick)
            RadioListTile<String>(
              value: 'folder',
              title: Text(strings.destinationFolder),
              subtitle: Text(folder?.name ?? strings.destinationFolderHint),
              secondary: folder == null
                  ? null
                  : TextButton(
                      onPressed: pick,
                      child: Text(strings.changeFolder),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Settings row: one file or the app's package. With [confirm], turning
/// one file on asks first (see [confirmHaulFormatFile]).
class HaulFormatTile extends StatelessWidget {
  const HaulFormatTile({
    super.key,
    required this.controller,
    this.confirm = false,
  });

  final HaulController controller;
  final bool confirm;

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    return _SettingsBuilder(
      controller: controller,
      builder: (context, edit, settings) => SwitchListTile(
        title: Text(strings.formatFile),
        subtitle: Text(strings.formatFileHint),
        value: settings.merge,
        onChanged: (merge) async {
          if (merge &&
              confirm &&
              !await confirmHaulFormatFile(context, controller)) {
            return;
          }
          edit.update((s) => s.copyWith(merge: merge));
        },
      ),
    );
  }
}

/// Before turning one file on: the file is put together at the end, with
/// the app open, beside the pieces — and how much is free, when known.
/// True when the user agreed.
Future<bool> confirmHaulFormatFile(
  BuildContext context,
  HaulController controller,
) async {
  final strings = controller.stringsOf(context);
  final free = await controller.android.freeBytes();
  if (!context.mounted) return false;
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(strings.formatFileConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.formatFileConfirm),
          if (free != null) ...[
            const SizedBox(height: 12),
            Text(
              strings.freeSpace(strings.bytes(free)),
              style: Theme.of(dialog).textTheme.titleSmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(strings.formatFileConfirmAction),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Settings row: where files go, opening the choice in a dialog. Says so
/// when a picked folder can no longer be written to. Nothing on iOS.
class HaulDestinationTile extends StatefulWidget {
  const HaulDestinationTile({super.key, required this.controller});

  final HaulController controller;

  @override
  State<HaulDestinationTile> createState() => _HaulDestinationTileState();
}

class _HaulDestinationTileState extends State<HaulDestinationTile> {
  HaulController get controller => widget.controller;

  /// Whether the picked folder still takes files; read when it changes.
  bool _lost = false;
  String? _checked;

  Future<void> _check(HaulDestination destination) async {
    final uri = switch (destination) {
      FolderDestination(:final folder) when controller.android.isAndroid =>
        folder.uri,
      _ => null,
    };
    if (uri == _checked) return;
    _checked = uri;
    final lost =
        uri != null && await controller.android.describeFolder(uri) == null;
    // Another folder was chosen meanwhile: its own check says.
    if (!mounted || _checked != uri) return;
    if (lost != _lost) setState(() => _lost = lost);
  }

  @override
  Widget build(BuildContext context) {
    if (!haulDestinationChoosable(controller)) return const SizedBox.shrink();
    final strings = controller.stringsOf(context);
    return _SettingsBuilder(
      controller: controller,
      builder: (context, edit, settings) {
        final destination = settings.destination;
        _check(destination);
        final label = switch (destination) {
          PublicDestination() => strings.destinationPublic,
          AppDestination() => strings.destinationApp,
          FolderDestination(:final folder) => folder.name,
        };
        return ListTile(
          title: Text(strings.destination),
          subtitle: Text(
            _lost ? strings.destinationFolderLost : label,
            style: _lost
                ? TextStyle(color: HaulTheme.of(context).errorOf(context))
                : null,
          ),
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text(strings.destination),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              content: HaulDestinationChoice(
                controller: controller,
                destination: destination,
                onChanged: (d) {
                  _checked = null;
                  edit.update((s) => s.copyWith(destination: d));
                  Navigator.pop(dialog);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Settings row: only on Wi-Fi.
class HaulWifiOnlyTile extends StatelessWidget {
  const HaulWifiOnlyTile({super.key, required this.controller});

  final HaulController controller;

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    return _SettingsBuilder(
      controller: controller,
      builder: (context, edit, settings) => SwitchListTile(
        title: Text(strings.wifiOnly),
        subtitle: Text(strings.wifiOnlyHint),
        value: settings.wifiOnly,
        onChanged: (wifiOnly) =>
            edit.update((s) => s.copyWith(wifiOnly: wifiOnly)),
      ),
    );
  }
}

/// Whether the battery saver leaves downloads alone, read again whenever
/// the app comes back to the front (the system's dialog takes it out).
class HaulBatteryBuilder extends StatefulWidget {
  const HaulBatteryBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  final HaulController controller;

  /// [free] is null while it is being read.
  final Widget Function(BuildContext context, bool? free, VoidCallback ask)
  builder;

  @override
  State<HaulBatteryBuilder> createState() => _HaulBatteryBuilderState();
}

class _HaulBatteryBuilderState extends State<HaulBatteryBuilder>
    with WidgetsBindingObserver {
  bool? _free;

  HaulAndroid get _android => widget.controller.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void didUpdateWidget(HaulBatteryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.android != _android) _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final free = await _android.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _free = free);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _free,
    () => _android.requestIgnoreBatteryOptimizations(),
  );
}

/// Settings row: let downloads run with the battery saver on. Only on
/// Android.
class HaulBatteryTile extends StatelessWidget {
  const HaulBatteryTile({super.key, required this.controller});

  final HaulController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.android.isAndroid) {
      return const SizedBox.shrink();
    }
    final strings = controller.stringsOf(context);
    return HaulBatteryBuilder(
      controller: controller,
      builder: (context, free, ask) => ListTile(
        title: Text(strings.battery),
        subtitle: Text(strings.batteryHint),
        trailing: free ?? true
            ? Text(free == null ? '' : strings.batteryDone)
            : OutlinedButton(
                onPressed: ask,
                child: Text(strings.batteryAction),
              ),
      ),
    );
  }
}

/// Before the first download: asks once for the format, where a file goes
/// and — on Android — to let downloads run with the battery saver on, and
/// remembers it was asked. Answers whether to go on: true straight away
/// once it was accepted, false when the user backs out. Needs
/// [HaulController.settings].
Future<bool> ensureHaulSetup(
  BuildContext context,
  HaulController controller, {
  bool showWifiOnly = false,
}) async {
  if (controller.requireSettings.value.setupDone) return true;
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        HaulSetupSheet(controller: controller, showWifiOnly: showWifiOnly),
  );
  return accepted ?? false;
}

/// The sheet [ensureHaulSetup] shows. Choices are kept here until the user
/// accepts, so backing out changes nothing.
class HaulSetupSheet extends StatefulWidget {
  const HaulSetupSheet({
    super.key,
    required this.controller,
    this.showWifiOnly = false,
  });

  final HaulController controller;
  final bool showWifiOnly;

  @override
  State<HaulSetupSheet> createState() => _HaulSetupSheetState();
}

class _HaulSetupSheetState extends State<HaulSetupSheet> {
  HaulController get controller => widget.controller;

  late HaulSettings _draft = controller.requireSettings.value;

  void _accept() {
    // Only what the sheet showed: the rest may have changed meanwhile.
    controller.requireSettings.update(
      (s) => s.copyWith(
        merge: _draft.merge,
        destination: _draft.destination,
        wifiOnly: widget.showWifiOnly ? _draft.wifiOnly : null,
        setupDone: true,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.stringsOf(context);
    final text = Theme.of(context).textTheme;

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Text(label, style: text.titleSmall),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.setupTitle, style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    strings.setupIntro,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            heading(strings.format),
            HaulFormatChoice(
              controller: controller,
              merge: _draft.merge,
              onChanged: (merge) =>
                  setState(() => _draft = _draft.copyWith(merge: merge)),
            ),
            // Where a file goes only matters for a file: a package always
            // stays in the app.
            if (_draft.merge && haulDestinationChoosable(controller)) ...[
              heading(strings.destination),
              HaulDestinationChoice(
                controller: controller,
                destination: _draft.destination,
                onChanged: (d) =>
                    setState(() => _draft = _draft.copyWith(destination: d)),
              ),
            ],
            if (widget.showWifiOnly)
              SwitchListTile(
                title: Text(strings.wifiOnly),
                subtitle: Text(strings.wifiOnlyHint),
                value: _draft.wifiOnly,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(wifiOnly: v)),
              ),
            if (controller.android.isAndroid)
              HaulBatteryBuilder(
                controller: controller,
                builder: (context, free, ask) => free ?? true
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading(strings.battery),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              strings.batteryHint,
                              style: text.bodySmall,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: ask,
                                icon: const Icon(Icons.battery_saver_outlined),
                                label: Text(strings.batteryAction),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(strings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _accept,
                    child: Text(strings.download),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
