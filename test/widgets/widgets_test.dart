import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:haul/widgets.dart';

/// Never answers: downloads stay reading their source.
class _SilentFetcher extends SourceFetcher {
  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) => Completer<FetchedResponse>().future;
}

const _loki = DownloadParent(id: 'loki', title: 'Loki');

DownloadRequest _request(String key, {DownloadParent? parent, int? season}) =>
    DownloadRequest(
      key: key,
      title: key,
      name: OutputName(baseName: key),
      source: SourceRequest(url: 'https://cdn.example/$key.mpd'),
      parent: parent,
      metadata: {'season': ?season},
    );

void main() {
  late Directory dir;
  late DownloadEngine engine;
  late FakeHaulAndroid android;
  late HaulSettingsController settings;
  late List<HaulSettings> stored;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('haul_widgets_test');
    engine = DownloadEngine(
      appSupport: () async => dir,
      transfer: FakeTransferClient(appSupport: dir),
      resolver: SourceResolver(fetcher: _SilentFetcher()),
      store: MemoryRecordStore(),
      ffmpeg: FakeFfmpeg(),
      logger: RecordingLogger(),
      thumbnails: null,
      images: null,
    );
    android = FakeHaulAndroid();
    stored = [];
    settings = HaulSettingsController(const HaulSettings(), stored.add);
  });

  tearDown(() async {
    await engine.dispose();
    await dir.delete(recursive: true);
  });

  HaulController haulWith({HaulStrings? strings}) => HaulController(
    engine: engine,
    settings: settings,
    android: android,
    strings: strings,
  );

  HaulController haul() => haulWith();

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> enqueue(WidgetTester tester, List<DownloadRequest> requests) =>
      tester.runAsync(() async {
        await engine.init();
        await engine.enqueueAll(requests);
      });

  group('HaulDownloadList', () {
    testWidgets('a parent is one row; a loose download its own', (
      tester,
    ) async {
      await enqueue(tester, [
        _request('e1', parent: _loki),
        _request('e2', parent: _loki),
        _request('film'),
      ]);
      ParentDownloads? opened;
      await tester.pumpWidget(
        app(
          HaulDownloadList(controller: haul(), onOpenParent: (p) => opened = p),
        ),
      );
      await tester.pump();

      expect(find.byType(HaulParentTile), findsOneWidget);
      expect(find.byType(HaulDownloadTile), findsOneWidget);
      expect(find.text('Loki'), findsOneWidget);
      expect(find.text(const HaulStrings().doneOf(0, 2)), findsOneWidget);

      await tester.tap(find.byType(HaulParentTile));
      expect(opened?.parent.id, 'loki');
    });

    testWidgets('empty says so, in the app strings', (tester) async {
      await tester.runAsync(engine.init);
      await tester.pumpWidget(
        app(
          HaulDownloadList(
            controller: haulWith(strings: const HaulStringsEs()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(const HaulStringsEs().empty), findsOneWidget);
    });

    testWidgets('builders replace the rows', (tester) async {
      await enqueue(tester, [_request('film')]);
      await tester.pumpWidget(
        app(
          HaulDownloadList(
            controller: haul(),
            itemBuilder: (context, id) =>
                Text('custom $id', key: const Key('row')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('row')), findsOneWidget);
      expect(find.byType(HaulDownloadTile), findsNothing);
    });
  });

  testWidgets('HaulParentView says it is empty once, however often it '
      'rebuilds', (tester) async {
    var emptied = 0;
    Widget view() => app(
      HaulParentView(
        controller: haul(),
        parentId: 'nobody',
        onEmpty: () => emptied++,
      ),
    );
    await tester.pumpWidget(view());
    await tester.pump();
    await tester.pumpWidget(view());
    await tester.pump();
    expect(emptied, 1);
  });

  testWidgets('HaulParentView heads children with what the app says', (
    tester,
  ) async {
    await enqueue(tester, [
      _request('Loki S02E01', parent: _loki, season: 2),
      _request('Loki S01E02', parent: _loki, season: 1),
      _request('Loki S01E01', parent: _loki, season: 1),
    ]);
    await tester.pumpWidget(
      app(
        HaulParentView(
          controller: haul(),
          parentId: 'loki',
          sectionOf: (r) => 'Season ${r.metadata['season']}',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Season 1'), lessThan(y('Loki S01E01')));
    expect(y('Loki S01E01'), lessThan(y('Loki S01E02')));
    expect(y('Loki S01E02'), lessThan(y('Season 2')));
    expect(y('Season 2'), lessThan(y('Loki S02E01')));
  });

  testWidgets('HaulParentView follows the app order when given', (
    tester,
  ) async {
    await enqueue(tester, [
      _request('a', parent: _loki, season: 1),
      _request('b', parent: _loki, season: 2),
    ]);
    await tester.pumpWidget(
      app(
        HaulParentView(
          controller: haul(),
          parentId: 'loki',
          sort: (x, y) => y.title.compareTo(x.title),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('b')).dy,
      lessThan(tester.getTopLeft(find.text('a')).dy),
    );
  });

  testWidgets('the tile pauses with its primary button', (tester) async {
    await enqueue(tester, [_request('film')]);
    await tester.pumpWidget(
      app(HaulDownloadTile(controller: haul(), id: engine.records.single.id)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip(const HaulStrings().pause));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(engine.records.single.status, DownloadStatus.paused);
    expect(find.byTooltip(const HaulStrings().resume), findsOneWidget);
  });

  group('menuItems', () {
    testWidgets('the app entries go before delete and get the record', (
      tester,
    ) async {
      await enqueue(tester, [_request('film')]);
      DownloadRecord? sent;
      await tester.pumpWidget(
        app(
          HaulDownloadTile(
            controller: haul(),
            id: engine.records.single.id,
            menuItems: (context, record) => [
              HaulMenuItem(
                icon: Icons.cast,
                label: 'Cast',
                onSelected: (_) => sent = record,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final labels = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(labels, [
        const HaulStrings().pause,
        'Cast',
        const HaulStrings().delete,
      ]);

      await tester.tap(find.text('Cast'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(sent?.id, engine.records.single.id);
    });

    testWidgets('a parent menu takes them too', (tester) async {
      var shared = false;
      await tester.pumpWidget(
        app(
          HaulParentActions(
            controller: haul(),
            parent: _loki,
            menuItems: (context, parent) => [
              HaulMenuItem(
                icon: Icons.share,
                label: 'Share ${parent.title}',
                onSelected: (_) => shared = true,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(PopupMenuButton<Object>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share Loki'));
      await tester.pumpAndSettle();
      expect(shared, isTrue);
    });
  });

  testWidgets('HaulDownloadButton asks the app to enqueue a new key', (
    tester,
  ) async {
    await tester.runAsync(engine.init);
    var asked = 0;
    await tester.pumpWidget(
      app(
        HaulDownloadButton(
          controller: haul(),
          downloadKey: 'film',
          onDownload: () async => asked++,
        ),
      ),
    );
    await tester.tap(find.byType(HaulDownloadButton));
    expect(asked, 1);
  });

  group('HaulParentDownloadButton', () {
    testWidgets('asks the app while nothing of the season is there', (
      tester,
    ) async {
      await tester.runAsync(engine.init);
      var asked = 0;
      await tester.pumpWidget(
        app(
          HaulParentDownloadButton(
            controller: haul(),
            parentId: 'loki',
            where: (r) => r.metadata['season'] == 1,
            onDownload: () async => asked++,
          ),
        ),
      );
      await tester.tap(find.byType(HaulParentDownloadButton));
      expect(asked, 1);
    });

    testWidgets('pauses the season, then resumes it', (tester) async {
      await enqueue(tester, [
        _request('s1e1', parent: _loki, season: 1),
        _request('s1e2', parent: _loki, season: 1),
        _request('s2e1', parent: _loki, season: 2),
      ]);
      await tester.pumpWidget(
        app(
          HaulParentDownloadButton(
            controller: haul(),
            parentId: 'loki',
            where: (r) => r.metadata['season'] == 1,
            onDownload: () async {},
          ),
        ),
      );
      await tester.pump();

      Future<void> tapAndSettle() async {
        await tester.tap(find.byType(HaulParentDownloadButton));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      await tapAndSettle();
      final statuses = {for (final r in engine.records) r.key: r.status};
      expect(statuses['s1e1'], DownloadStatus.paused);
      expect(statuses['s1e2'], DownloadStatus.paused);
      expect(statuses['s2e1'], isNot(DownloadStatus.paused));
      expect(
        find.byTooltip(RegExp(const HaulStrings().resumeAll)),
        findsOneWidget,
      );

      await tapAndSettle();
      expect(engine.byKey('s1e1')!.status, isNot(DownloadStatus.paused));
    });
  });

  group('HaulFormatTile', () {
    testWidgets('switches straight away by default', (tester) async {
      await tester.pumpWidget(app(HaulFormatTile(controller: haul())));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(settings.value.merge, isTrue);
    });

    testWidgets('with confirm, asks before turning one file on', (
      tester,
    ) async {
      android.free = 2000000000;
      await tester.pumpWidget(
        app(HaulFormatTile(controller: haul(), confirm: true)),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text(const HaulStrings().freeSpace('2.0 GB')), findsOne);
      await tester.tap(find.text(const HaulStrings().cancel));
      await tester.pumpAndSettle();
      expect(settings.value.merge, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const HaulStrings().formatFileConfirmAction));
      await tester.pumpAndSettle();
      expect(settings.value.merge, isTrue);

      // Turning it off asks nothing.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(settings.value.merge, isFalse);
    });
  });

  group('ensureHaulSetup', () {
    Future<void> tapText(WidgetTester tester, String text) async {
      final finder = find.text(text);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<bool?> open(WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ensureHaulSetup(context, haul()),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tapText(tester, 'go');
      return result;
    }

    testWidgets('once accepted it answers true without asking', (tester) async {
      settings.value = const HaulSettings(setupDone: true);
      await tester.pumpWidget(app(const SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      expect(await ensureHaulSetup(context, haul()), isTrue);
      expect(find.byType(HaulSetupSheet), findsNothing);
    });

    testWidgets('accepting keeps the choices and marks it done', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(HaulSetupSheet), findsOneWidget);

      await tapText(tester, const HaulStrings().formatFile);
      await tapText(tester, const HaulStrings().destinationApp);
      await tapText(tester, const HaulStrings().download);

      expect(settings.value.merge, isTrue);
      expect(settings.value.destination, const HaulDestination.app());
      expect(settings.value.setupDone, isTrue);
      expect(stored.last, settings.value);
    });

    testWidgets('accepting keeps what the sheet did not show', (tester) async {
      await open(tester);
      settings.update((s) => s.copyWith(wifiOnly: true));
      await tapText(tester, const HaulStrings().download);
      expect(settings.value.wifiOnly, isTrue);
      expect(settings.value.setupDone, isTrue);
    });

    testWidgets('backing out changes nothing', (tester) async {
      await open(tester);
      await tapText(tester, const HaulStrings().formatFile);
      await tapText(tester, const HaulStrings().cancel);

      expect(settings.value, const HaulSettings());
      expect(stored, isEmpty);
    });

    testWidgets('a picked folder becomes the destination', (tester) async {
      android.picked = const HaulFolder(
        uri: 'content://tree/x',
        name: 'Movies',
      );
      await open(tester);
      await tapText(tester, const HaulStrings().formatFile);
      await tapText(tester, const HaulStrings().destinationFolder);

      expect(find.text('Movies'), findsOneWidget);
      await tapText(tester, const HaulStrings().download);
      expect(
        settings.value.destination,
        const HaulDestination.folder(
          HaulFolder(uri: 'content://tree/x', name: 'Movies'),
        ),
      );
    });

    testWidgets('the battery row asks the system', (tester) async {
      await open(tester);
      await tapText(tester, const HaulStrings().batteryAction);
      expect(android.batteryRequests, 1);
    });
  });

  testWidgets('HaulBatteryTile is hidden once allowed, and off Android', (
    tester,
  ) async {
    android.batteryFree = true;
    await tester.pumpWidget(app(HaulBatteryTile(controller: haul())));
    await tester.pump();
    expect(find.text(const HaulStrings().batteryAction), findsNothing);
    expect(find.text(const HaulStrings().batteryDone), findsOneWidget);

    android = FakeHaulAndroid(isAndroid: false);
    await tester.pumpWidget(app(HaulBatteryTile(controller: haul())));
    expect(find.byType(ListTile), findsNothing);
  });
}
