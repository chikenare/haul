import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:haul/haul.dart';
import 'package:haul/widgets.dart';
import 'package:haul_example/catalog.dart';
import 'package:haul_example/player_screen.dart';

/// The example keeps it in a global; an app keeps it however it keeps its
/// state (a Riverpod provider, a service locator…) and hands it to each of
/// haul's widgets.
late final HaulController haul;

/// The example's settings, kept in memory: haul only takes their values.
/// An app keeps them wherever it keeps its preferences, with its own rows
/// to change them.
final merge = ValueNotifier(false);
final wifiOnly = ValueNotifier(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = DownloadEngine(
    // No `folder`: the platform's default, written with no permission. An
    // app passes the one the user picked (`folder: () async => path`).
    sink: HaulOutputSink(subfolder: 'Haul Example'),
    wifiOnly: wifiOnly,
    // Small: the example is for trying things, not for filling the phone.
    criteria: (_) async => const TrackCriteria(maxHeight: 480),
  );
  await engine.init();
  haul = HaulController(engine: engine);

  runApp(const ExampleApp());
}

/// What a download asked for now becomes: one file, or the package.
OutputMode output(BuildContext context) => merge.value
    ? OutputMode(
        kind: OutputKind.file,
        subtitleSidecars: Theme.of(context).platform == TargetPlatform.android,
      )
    : OutputMode.package;

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
          controller: haul,
          onPlay: (record) => openPlayer(context, record),
          // A parent opens in place; headings from the app's own data, and
          // the titles already sort.
          sectionOf: (r) => switch (seasonOf(r)) {
            final season? => 'Season $season',
            null => null,
          },
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
    return ListTile(
      title: Text(item.listTitle),
      subtitle: Text(item.kind),
      // Its progress is on the Downloads tab, haul's list.
      trailing: IconButton(
        icon: const Icon(Icons.download),
        onPressed: () => haul.engine.enqueue(item.request(output(context))),
      ),
    );
  }
}

/// A whole season at once: what is there already is left as it is.
class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.season});

  final int season;

  @override
  Widget build(BuildContext context) {
    final items = episodes.where((e) => e.season == season).toList();
    return ListTile(
      title: Text('Season $season'),
      trailing: IconButton(
        icon: const Icon(Icons.download_for_offline),
        onPressed: () => haul.engine.enqueueAll([
          for (final item in items) item.request(output(context)),
        ]),
      ),
    );
  }
}

/// The example's own rows: haul has no settings screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget toggle(String title, ValueNotifier<bool> value) =>
        ValueListenableBuilder(
          valueListenable: value,
          builder: (context, on, _) => SwitchListTile(
            title: Text(title),
            value: on,
            onChanged: (v) => value.value = v,
          ),
        );
    return ListView(
      children: [
        toggle('Save as one file', merge),
        toggle('Only on Wi-Fi', wifiOnly),
      ],
    );
  }
}
