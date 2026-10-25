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

const _loki = DownloadGroup(id: 'loki', title: 'Loki');

DownloadRequest _request(
  String key, {
  DownloadGroup? group,
  String? section,
  num? order,
}) => DownloadRequest(
  key: key,
  title: key,
  name: OutputName(baseName: key),
  source: SourceRequest(url: 'https://cdn.example/$key.mpd'),
  group: group,
  section: section,
  order: order,
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
    );
    android = FakeHaulAndroid();
    stored = [];
    settings = HaulSettingsController(const HaulSettings(), stored.add);
  });

  tearDown(() async {
    await engine.dispose();
    await dir.delete(recursive: true);
  });

  Widget app(Widget child, {HaulStrings? strings}) => HaulScope(
    engine: engine,
    settings: settings,
    android: android,
    strings: strings,
    child: MaterialApp(home: Scaffold(body: child)),
  );

  Future<void> enqueue(WidgetTester tester, List<DownloadRequest> requests) =>
      tester.runAsync(() async {
        await engine.init();
        await engine.enqueueAll(requests);
      });

  group('HaulDownloadList', () {
    testWidgets('a group is one row; a loose download its own', (tester) async {
      await enqueue(tester, [
        _request('e1', group: _loki, section: '1', order: 1),
        _request('e2', group: _loki, section: '1', order: 2),
        _request('film'),
      ]);
      GroupedDownloads? opened;
      await tester.pumpWidget(
        app(HaulDownloadList(onOpenGroup: (g) => opened = g)),
      );
      await tester.pump();

      expect(find.byType(HaulGroupTile), findsOneWidget);
      expect(find.byType(HaulDownloadTile), findsOneWidget);
      expect(find.text('Loki'), findsOneWidget);
      expect(
        find.text(const HaulStrings().downloads(2), findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.byType(HaulGroupTile));
      expect(opened?.group.id, 'loki');
    });

    testWidgets('empty says so, in the app strings', (tester) async {
      await tester.runAsync(engine.init);
      await tester.pumpWidget(
        app(const HaulDownloadList(), strings: const HaulStringsEs()),
      );
      await tester.pump();
      expect(find.text(const HaulStringsEs().empty), findsOneWidget);
    });

    testWidgets('builders replace the rows', (tester) async {
      await enqueue(tester, [_request('film')]);
      await tester.pumpWidget(
        app(
          HaulDownloadList(
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

  testWidgets('HaulGroupView heads each section with HaulStrings.section', (
    tester,
  ) async {
    await enqueue(tester, [
      _request('s2e1', group: _loki, section: '2', order: 1),
      _request('s1e1', group: _loki, section: '1', order: 1),
    ]);
    await tester.pumpWidget(
      app(
        const HaulGroupView(groupId: 'loki'),
        strings: const _SeasonStrings(),
      ),
    );
    await tester.pump();

    final season1 = tester.getTopLeft(find.text('Season 1'));
    final season2 = tester.getTopLeft(find.text('Season 2'));
    expect(season1.dy, lessThan(season2.dy));
    expect(find.byType(HaulDownloadTile), findsNWidgets(2));
  });

  testWidgets('the tile pauses with its primary button', (tester) async {
    await enqueue(tester, [_request('film')]);
    await tester.pumpWidget(
      app(HaulDownloadTile(id: engine.records.single.id)),
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

  testWidgets('HaulDownloadButton asks the app to enqueue a new key', (
    tester,
  ) async {
    await tester.runAsync(engine.init);
    var asked = 0;
    await tester.pumpWidget(
      app(
        HaulDownloadButton(
          downloadKey: 'film',
          onDownload: () async => asked++,
        ),
      ),
    );
    await tester.tap(find.byType(HaulDownloadButton));
    expect(asked, 1);
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
              onPressed: () async => result = await ensureHaulSetup(context),
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
      expect(await ensureHaulSetup(context), isTrue);
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
    await tester.pumpWidget(app(const HaulBatteryTile()));
    await tester.pump();
    expect(find.text(const HaulStrings().batteryAction), findsNothing);
    expect(find.text(const HaulStrings().batteryDone), findsOneWidget);

    android = FakeHaulAndroid(isAndroid: false);
    await tester.pumpWidget(app(const HaulBatteryTile()));
    expect(find.byType(ListTile), findsNothing);
  });
}

class _SeasonStrings extends HaulStrings {
  const _SeasonStrings();

  @override
  String section(String id) => 'Season $id';
}
