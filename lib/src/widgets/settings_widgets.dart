import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/haul_output_sink.dart';
import 'package:haul/src/widgets/haul_scope.dart';
import 'package:haul/src/widgets/haul_settings.dart';

bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Whether the destination can be chosen here: Android, and desktop. iOS
/// keeps files in the app.
bool haulDestinationChoosable(HaulScope scope) =>
    scope.android.isAndroid || _desktop;

/// Asks the platform for a folder: SAF on Android, the app's
/// `HaulScope.pickDirectory` on desktop. Null when the user backs out or
/// there is no way to pick one.
Future<HaulFolder?> pickHaulFolder(
  HaulScope scope, {
  HaulDestination? current,
}) async {
  if (scope.android.isAndroid) {
    try {
      return await scope.android.pickFolder(
        initialUri: switch (current) {
          FolderDestination(:final folder) => folder.uri,
          _ => null,
        },
      );
    } on Exception {
      return null;
    }
  }
  final path = await scope.pickDirectory?.call();
  return path == null ? null : HaulFolder(uri: path, name: path);
}

HaulSettingsController _settingsOf(BuildContext context) {
  final settings = HaulScope.of(context).settings;
  assert(settings != null, 'HaulScope.settings is needed here');
  return settings!;
}

/// Follows [HaulScope.settings].
class _SettingsBuilder extends StatelessWidget {
  const _SettingsBuilder({required this.builder});

  final Widget Function(
    BuildContext context,
    HaulSettingsController controller,
    HaulSettings settings,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    final controller = _settingsOf(context);
    return ValueListenableBuilder<HaulSettings>(
      valueListenable: controller,
      builder: (context, settings, _) => builder(context, controller, settings),
    );
  }
}

/// The choice of format as two radio rows, for a sheet or a page.
class HaulFormatChoice extends StatelessWidget {
  const HaulFormatChoice({
    super.key,
    required this.merge,
    required this.onChanged,
  });

  final bool merge;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = HaulScope.stringsOf(context);
    return RadioGroup<bool>(
      groupValue: merge,
      onChanged: (value) => onChanged(value ?? false),
      child: Column(
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
    required this.destination,
    required this.onChanged,
  });

  final HaulDestination destination;
  final ValueChanged<HaulDestination> onChanged;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final strings = HaulScope.stringsOf(context);
    final canPick = scope.android.isAndroid || scope.pickDirectory != null;
    final folder = switch (destination) {
      FolderDestination(:final folder) => folder,
      _ => null,
    };

    Future<void> pick() async {
      final picked = await pickHaulFolder(scope, current: destination);
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

/// Settings row: one file or the app's package.
class HaulFormatTile extends StatelessWidget {
  const HaulFormatTile({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = HaulScope.stringsOf(context);
    return _SettingsBuilder(
      builder: (context, controller, settings) => SwitchListTile(
        title: Text(strings.formatFile),
        subtitle: Text(strings.formatFileHint),
        value: settings.merge,
        onChanged: (merge) =>
            controller.update((s) => s.copyWith(merge: merge)),
      ),
    );
  }
}

/// Settings row: where files go, opening the choice in a dialog. Says so
/// when a picked folder can no longer be written to. Nothing on iOS.
class HaulDestinationTile extends StatefulWidget {
  const HaulDestinationTile({super.key});

  @override
  State<HaulDestinationTile> createState() => _HaulDestinationTileState();
}

class _HaulDestinationTileState extends State<HaulDestinationTile> {
  /// Whether the picked folder still takes files; read when it changes.
  bool _lost = false;
  String? _checked;

  Future<void> _check(HaulScope scope, HaulDestination destination) async {
    final uri = switch (destination) {
      FolderDestination(:final folder) when scope.android.isAndroid =>
        folder.uri,
      _ => null,
    };
    if (uri == _checked) return;
    _checked = uri;
    final lost = uri != null && await scope.android.describeFolder(uri) == null;
    if (mounted && lost != _lost) setState(() => _lost = lost);
  }

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    if (!haulDestinationChoosable(scope)) return const SizedBox.shrink();
    final strings = HaulScope.stringsOf(context);
    return _SettingsBuilder(
      builder: (context, controller, settings) {
        final destination = settings.destination;
        _check(scope, destination);
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
                destination: destination,
                onChanged: (d) {
                  _checked = null;
                  controller.update((s) => s.copyWith(destination: d));
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
  const HaulWifiOnlyTile({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = HaulScope.stringsOf(context);
    return _SettingsBuilder(
      builder: (context, controller, settings) => SwitchListTile(
        title: Text(strings.wifiOnly),
        subtitle: Text(strings.wifiOnlyHint),
        value: settings.wifiOnly,
        onChanged: (wifiOnly) =>
            controller.update((s) => s.copyWith(wifiOnly: wifiOnly)),
      ),
    );
  }
}

/// Whether the battery saver leaves downloads alone, read again whenever
/// the app comes back to the front (the system's dialog takes it out).
class HaulBatteryBuilder extends StatefulWidget {
  const HaulBatteryBuilder({super.key, required this.builder});

  /// [free] is null while it is being read.
  final Widget Function(BuildContext context, bool? free, VoidCallback ask)
  builder;

  @override
  State<HaulBatteryBuilder> createState() => _HaulBatteryBuilderState();
}

class _HaulBatteryBuilderState extends State<HaulBatteryBuilder>
    with WidgetsBindingObserver {
  bool? _free;
  HaulAndroid? _android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final android = HaulScope.of(context).android;
    if (android != _android) {
      _android = android;
      _read();
    }
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
    final free = await _android!.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _free = free);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _free,
    () => _android!.requestIgnoreBatteryOptimizations(),
  );
}

/// Settings row: let downloads run with the battery saver on. Only on
/// Android.
class HaulBatteryTile extends StatelessWidget {
  const HaulBatteryTile({super.key});

  @override
  Widget build(BuildContext context) {
    if (!HaulScope.of(context).android.isAndroid) {
      return const SizedBox.shrink();
    }
    final strings = HaulScope.stringsOf(context);
    return HaulBatteryBuilder(
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
/// [HaulScope.settings].
Future<bool> ensureHaulSetup(
  BuildContext context, {
  bool showWifiOnly = false,
}) async {
  final controller = _settingsOf(context);
  if (controller.value.setupDone) return true;
  final scope = HaulScope.of(context);
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The sheet is pushed above the scope's subtree on the root navigator:
    // it gets the scope again explicitly.
    builder: (_) => HaulScope(
      engine: scope.engine,
      settings: scope.settings,
      strings: scope.strings,
      android: scope.android,
      pickDirectory: scope.pickDirectory,
      canRetry: scope.canRetry,
      child: HaulSetupSheet(showWifiOnly: showWifiOnly),
    ),
  );
  return accepted ?? false;
}

/// The sheet [ensureHaulSetup] shows. Choices are kept here until the user
/// accepts, so backing out changes nothing.
class HaulSetupSheet extends StatefulWidget {
  const HaulSetupSheet({super.key, this.showWifiOnly = false});

  final bool showWifiOnly;

  @override
  State<HaulSetupSheet> createState() => _HaulSetupSheetState();
}

class _HaulSetupSheetState extends State<HaulSetupSheet> {
  late HaulSettings _draft = _settingsOf(context).value;

  void _accept() {
    _settingsOf(context).update((_) => _draft.copyWith(setupDone: true));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final strings = HaulScope.stringsOf(context);
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
              merge: _draft.merge,
              onChanged: (merge) =>
                  setState(() => _draft = _draft.copyWith(merge: merge)),
            ),
            // Where a file goes only matters for a file: a package always
            // stays in the app.
            if (_draft.merge && haulDestinationChoosable(scope)) ...[
              heading(strings.destination),
              HaulDestinationChoice(
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
            if (scope.android.isAndroid)
              HaulBatteryBuilder(
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
