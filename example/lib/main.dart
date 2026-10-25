import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:haul/haul.dart';
import 'package:haul/widgets.dart';
import 'package:haul_example/catalog.dart';
import 'package:haul_example/player_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _settingsKey = 'haul.settings';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // haul keeps nothing of the settings: the app stores them its own way.
  final settings = HaulSettingsController(switch (prefs.getString(
    _settingsKey,
  )) {
    final json? => HaulSettings.fromJson(
      jsonDecode(json) as Map<String, Object?>,
    ),
    null => const HaulSettings(),
  }, (s) => prefs.setString(_settingsKey, jsonEncode(s.toJson())));

  final engine = DownloadEngine(
    sink: HaulOutputSink(
      destination: () async => settings.value.destination,
      subfolder: 'Haul Example',
    ),
    wifiOnly: settings.wifiOnly,
    // Small: the example is for trying things, not for filling the phone.
    criteria: (_) async => const TrackCriteria(maxHeight: 480),
  );
  await engine.init();

  runApp(ExampleApp(engine: engine, settings: settings));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.engine, required this.settings});

  final DownloadEngine engine;
  final HaulSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return HaulScope(
      engine: engine,
      settings: settings,
      strings: const _ExampleStrings(),
      child: MaterialApp(
        title: 'haul example',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('es')],
        home: const HomeScreen(),
      ),
    );
  }
}

/// Spanish when the phone is in Spanish, through the built-in strings; the
/// sections are labelled here, as an app would.
class _ExampleStrings extends HaulStrings {
  const _ExampleStrings();

  @override
  String section(String id) => 'Season $id';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'Catalog',
          1 => 'Downloads',
          _ => 'Settings',
        }),
      ),
      body: switch (_tab) {
        0 => const CatalogScreen(),
        1 => HaulDownloadList(
          onPlay: (record) => openPlayer(context, record),
          onOpenGroup: (group) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupScreen(group: group.group),
            ),
          ),
        ),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library),
            label: 'Catalog',
          ),
          NavigationDestination(icon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _Heading('Movies'),
        for (final item in movies) _CatalogRow(item: item),
        _Heading('${clips.title} (a group in two seasons)'),
        for (final item in episodes) _CatalogRow(item: item),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.item});

  final SampleItem item;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    return ListTile(
      leading: HaulThumbnail(
        imageUrl: item.imageUrl ?? item.group?.imageUrl,
        size: const Size(72, 40),
      ),
      title: Text(
        item.section == null
            ? item.title
            : 'S${item.section}E${item.order} · ${item.title}',
      ),
      subtitle: Text(item.kind),
      trailing: HaulDownloadButton(
        downloadKey: item.key,
        onPlay: (record) => openPlayer(context, record),
        onDownload: () async {
          final android = Theme.of(context).platform == TargetPlatform.android;
          // The first time, the user picks format and folder.
          if (!await ensureHaulSetup(context, showWifiOnly: true)) return;
          await scope.engine.enqueue(
            item.request(
              scope.settings!.value.output(subtitleSidecars: android),
            ),
          );
        },
      ),
    );
  }
}

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.group});

  final DownloadGroup group;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.title),
        actions: [HaulGroupActions(group: group)],
      ),
      body: HaulGroupView(
        groupId: group.id,
        onPlay: (record) => openPlayer(context, record),
        onEmpty: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = HaulScope.of(context).settings!;
    return ListView(
      children: [
        const HaulFormatTile(),
        const HaulDestinationTile(),
        const HaulWifiOnlyTile(),
        const HaulBatteryTile(),
        ListTile(
          title: const Text('Show the first-download sheet again'),
          onTap: () => settings.update((s) => s.copyWith(setupDone: false)),
        ),
      ],
    );
  }
}
