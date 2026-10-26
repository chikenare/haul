import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/src/widgets/download_widgets.dart';
import 'package:haul/src/widgets/haul_controller.dart';
import 'package:haul/src/widgets/haul_strings.dart';
import 'package:haul/src/widgets/parent_widgets.dart';
import 'package:haul/testing.dart';

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
  });

  tearDown(() async {
    await engine.dispose();
    await dir.delete(recursive: true);
  });

  HaulController haulWith({HaulStrings? strings}) =>
      HaulController(engine: engine, android: android, strings: strings);

  HaulController haul() => haulWith();

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> enqueue(WidgetTester tester, List<DownloadRequest> requests) =>
      tester.runAsync(() async {
        await engine.init();
        await engine.enqueueAll(requests);
      });

  group('HaulDownloadList', () {
    testWidgets('a parent is one row that opens there into its children', (
      tester,
    ) async {
      await enqueue(tester, [
        _request('e1', parent: _loki),
        _request('e2', parent: _loki),
        _request('film'),
      ]);
      await tester.pumpWidget(app(HaulDownloadList(controller: haul())));
      await tester.pump();

      expect(find.byType(HaulParentTile), findsOneWidget);
      expect(find.byType(HaulDownloadTile), findsOneWidget);
      expect(find.text('Loki'), findsOneWidget);
      expect(find.text(const HaulStrings().doneOf(0, 2)), findsOneWidget);
      expect(find.text('e1'), findsNothing);

      await tester.tap(find.text('Loki'));
      await tester.pump();
      expect(find.text('e1'), findsOneWidget);
      expect(find.text('e2'), findsOneWidget);

      await tester.tap(find.text('Loki'));
      await tester.pump();
      expect(find.text('e1'), findsNothing);
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

  Future<void> openLoki(WidgetTester tester, Widget list) async {
    await tester.pumpWidget(app(list));
    await tester.pump();
    await tester.tap(find.text('Loki'));
    await tester.pump();
  }

  testWidgets('an open parent heads its children with what the app says', (
    tester,
  ) async {
    await enqueue(tester, [
      _request('Loki S02E01', parent: _loki, season: 2),
      _request('Loki S01E02', parent: _loki, season: 1),
      _request('Loki S01E01', parent: _loki, season: 1),
    ]);
    await openLoki(
      tester,
      HaulDownloadList(
        controller: haul(),
        sectionOf: (r) => 'Season ${r.metadata['season']}',
      ),
    );

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Season 1'), lessThan(y('Loki S01E01')));
    expect(y('Loki S01E01'), lessThan(y('Loki S01E02')));
    expect(y('Loki S01E02'), lessThan(y('Season 2')));
    expect(y('Season 2'), lessThan(y('Loki S02E01')));
  });

  testWidgets('an open parent follows the app order when given', (
    tester,
  ) async {
    await enqueue(tester, [
      _request('a', parent: _loki, season: 1),
      _request('b', parent: _loki, season: 2),
    ]);
    await openLoki(
      tester,
      HaulDownloadList(
        controller: haul(),
        sort: (x, y) => y.title.compareTo(x.title),
      ),
    );
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
      await enqueue(tester, [_request('e1', parent: _loki)]);
      var shared = false;
      await tester.pumpWidget(
        app(
          HaulDownloadList(
            controller: haul(),
            parentMenuItems: (context, parent) => [
              HaulMenuItem(
                icon: Icons.share,
                label: 'Share ${parent.title}',
                onSelected: (_) => shared = true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(HaulParentTile),
          matching: find.byType(PopupMenuButton<Object>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(const HaulStrings().pauseAll), findsOneWidget);
      await tester.tap(find.text('Share Loki'));
      await tester.pumpAndSettle();
      expect(shared, isTrue);
    });
  });
}
