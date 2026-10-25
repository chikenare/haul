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

/// The season of an episode, from what the example keeps in `metadata`.
int? seasonOf(DownloadRecord record) => record.metadata['season'] as int?;

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
          onOpenParent: (entry) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ParentScreen(parent: entry.parent),
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
        _Heading('${clips.title} (a parent, two seasons)'),
        for (final season in [1, 2]) ...[
          _SeasonRow(season: season),
          for (final item in episodes.where((e) => e.season == season))
            _CatalogRow(item: item),
        ],
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
        imageUrl: item.imageUrl ?? item.parent?.imageUrl,
        size: const Size(72, 40),
      ),
      title: Text(item.listTitle),
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

/// A whole season at once: the parent's button for some of its children.
class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.season});

  final int season;

  @override
  Widget build(BuildContext context) {
    final scope = HaulScope.of(context);
    final items = episodes.where((e) => e.season == season).toList();
    bool inSeason(DownloadRecord r) => seasonOf(r) == season;
    return ListTile(
      title: Text('Season $season'),
      subtitle: HaulParentProgressBuilder(
        parentId: clips.id,
        where: inSeason,
        builder: (context, progress) => Text(
          HaulScope.stringsOf(context).doneOf(progress.done, items.length),
        ),
      ),
      trailing: HaulParentDownloadButton(
        parentId: clips.id,
        where: inSeason,
        onDownload: () async {
          final android = Theme.of(context).platform == TargetPlatform.android;
          if (!await ensureHaulSetup(context, showWifiOnly: true)) return;
          // What is there already is left as it is.
          await scope.engine.enqueueAll([
            for (final item in items)
              item.request(
                scope.settings!.value.output(subtitleSidecars: android),
              ),
          ]);
        },
      ),
    );
  }
}

class ParentScreen extends StatelessWidget {
  const ParentScreen({super.key, required this.parent});

  final DownloadParent parent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(parent.title),
        actions: [HaulParentActions(parent: parent)],
      ),
      body: HaulParentView(
        parentId: parent.id,
        // Headings from the app's own data; the titles already sort.
        sectionOf: (r) => switch (seasonOf(r)) {
          final season? => 'Season $season',
          null => null,
        },
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
