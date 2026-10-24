import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';

import 'engine_test_support.dart';

void main() {
  late Env env;
  late ValueNotifier<bool> wifiOnly;
  late FakeWifiMonitor wifi;

  setUp(() {
    env = Env();
    wifiOnly = ValueNotifier(true);
    wifi = FakeWifiMonitor();
    addTearDown(wifiOnly.dispose);
  });

  Future<DownloadEngine> wifiEngine({FakeWifiMonitor? monitor}) =>
      env.engine(wifiOnly: wifiOnly, wifi: monitor ?? wifi);

  test(
    'without the setting, pieces may use any network and nothing waits',
    () async {
      wifi.set(false);
      final engine = await env.engine(wifi: wifi);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);

      expect(engine.waitingForWifi, isFalse);
      expect(
        env.transfer.enqueued.map((t) => t.requiresWiFi),
        everyElement(false),
      );
      await env.transfer.completeAll();
      await waitForStatus(engine, id, DownloadStatus.done);
    },
  );

  test('on Wi-Fi, every piece is handed over requiring it', () async {
    final engine = await wifiEngine();
    await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    expect(engine.waitingForWifi, isFalse);
    expect(
      env.transfer.enqueued.map((t) => t.requiresWiFi),
      everyElement(true),
    );
  });

  test('off Wi-Fi, nothing starts — not even reading the source — until it '
      'returns', () async {
    wifi.set(false);
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await settle();

    expect(engine.waitingForWifi, isTrue);
    expect(engine.byId(id)!.status, DownloadStatus.queued);
    expect(env.fetcher.requested, isEmpty);
    expect(env.transfer.enqueued, isEmpty);

    wifi.set(true);
    await waitUntil(() => env.transfer.enqueued.length == 6);
    expect(engine.waitingForWifi, isFalse);
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
  });

  test('Wi-Fi gone while downloading: back to the queue with its files, and '
      'on with only what is missing when it returns', () async {
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.complete(env.transfer.enqueued[0]);
    await waitUntil(() => engine.byId(id)!.progress.donePieces == 1);

    final changes = <bool>[];
    final sub = engine.watchAll().listen((_) {
      changes.add(engine.waitingForWifi);
    });
    addTearDown(sub.cancel);
    await settle();

    wifi.set(false);
    await waitForStatus(engine, id, DownloadStatus.queued);
    await waitUntil(() => env.inFlightOf(id).isEmpty);
    expect(engine.byId(id)!.progress.donePieces, 1);
    expect(changes, contains(true), reason: 'watchAll tells the UI');

    env.transfer.enqueued.clear();
    wifi.set(true);
    await waitUntil(() => env.transfer.enqueued.length == 5);
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
  });

  test('a piece failing because the platform saw Wi-Fi go first is not a '
      'failure', () async {
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    // The plugin's retries ran out before the app heard of the drop.
    wifi.set(false, announce: false);
    env.transfer.fail(
      env.transfer.enqueued.first,
      description: 'Task was stopped by the system',
    );
    await waitForStatus(engine, id, DownloadStatus.queued);
    expect(engine.waitingForWifi, isTrue);
    expect(engine.byId(id)!.error, isNull);
    await waitUntil(() => env.inFlightOf(id).isEmpty);

    wifi.set(true);
    await waitUntil(() => env.inFlightOf(id).length == 6);
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
  });

  test('a piece failing on Wi-Fi is still a network error', () async {
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    env.transfer.fail(env.transfer.enqueued.first, description: 'reset');
    final failed = await waitForStatus(engine, id, DownloadStatus.failed);
    expect(failed.error!.code, DownloadErrorCode.network);
  });

  test('an HTTP refusal off Wi-Fi is still the server\'s', () async {
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);

    wifi.set(false, announce: false);
    env.transfer.fail(env.transfer.enqueued.first, httpStatus: 500);
    final failed = await waitForStatus(engine, id, DownloadStatus.failed);
    expect(failed.error!.httpStatus, 500);
  });

  test(
    'without a monitor the drop cannot be told apart: a network error',
    () async {
      final engine = await env.engine(wifiOnly: wifiOnly);
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);

      env.transfer.fail(env.transfer.enqueued.first, description: 'stopped');
      final failed = await waitForStatus(engine, id, DownloadStatus.failed);
      expect(failed.error!.code, DownloadErrorCode.network);
    },
  );

  test('changing the setting asks for the pieces in flight again under the '
      'new one, keeping what is on disk', () async {
    final engine = await wifiEngine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.complete(env.transfer.enqueued[0]);
    await waitUntil(() => engine.byId(id)!.progress.donePieces == 1);

    env.transfer.enqueued.clear();
    wifiOnly.value = false;
    await waitUntil(() => env.transfer.enqueued.length == 5);
    expect(
      env.transfer.enqueued.map((t) => t.requiresWiFi),
      everyElement(false),
    );
    expect(env.inFlightOf(id), hasLength(5));

    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
  });

  test(
    'turning it on while off Wi-Fi stops the download where it is',
    () async {
      wifiOnly.value = false;
      wifi.set(false);
      final engine = await wifiEngine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await waitUntil(() => env.transfer.enqueued.length == 6);

      wifiOnly.value = true;
      await waitForStatus(engine, id, DownloadStatus.queued);
      await waitUntil(() => env.inFlightOf(id).isEmpty);
      expect(engine.waitingForWifi, isTrue);
    },
  );

  test(
    'a user pause while waiting for Wi-Fi stays paused when it returns',
    () async {
      wifi.set(false);
      final engine = await wifiEngine();
      final (:id, outcome: _) = await engine.enqueue(request());
      await settle();
      await engine.pause(id);

      wifi.set(true);
      await settle();
      expect(engine.byId(id)!.status, DownloadStatus.paused);
      expect(env.transfer.enqueued, isEmpty);
    },
  );
}
