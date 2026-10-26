import 'dart:ui' show Locale;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

import '../engine/engine_test_support.dart';

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final shown = <(int, String?, String?)>[];
  final cancelled = <int>[];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async => shown.add((id, title, body));

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Env env;
  late _FakePlugin plugin;
  late HaulNotifications notifications;

  setUp(() {
    env = Env();
    plugin = _FakePlugin();
    notifications = HaulNotifications(
      icon: 'ic_stat_download',
      texts: const HaulNotificationTexts(failed: 'Failed'),
      plugin: plugin,
    );
  });

  test('a download in pieces: its progress, then gone when it is', () async {
    final engine = await env.engine();
    await notifications.follow(engine);
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.complete(env.transfer.enqueued.first);
    await waitUntil(() => plugin.shown.isNotEmpty);

    expect(plugin.shown.last.$2, 'La Película');
    expect(plugin.shown.last.$3, endsWith('%'));

    await engine.delete(id);
    await waitUntil(() => plugin.cancelled.isNotEmpty);
  });

  test('a failure is said once', () async {
    final engine = await env.engine();
    await notifications.follow(engine);
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    env.transfer.fail(env.transfer.enqueued.first, httpStatus: 500);
    await waitForStatus(engine, id, DownloadStatus.failed);
    await waitUntil(() => plugin.shown.any((n) => n.$3 == 'Failed'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(plugin.shown.where((n) => n.$3 == 'Failed'), hasLength(1));
  });

  test('what failed before it followed is not said again', () async {
    final engine = await env.engine(json: true);
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    env.transfer.fail(env.transfer.enqueued.first, httpStatus: 500);
    await waitForStatus(engine, id, DownloadStatus.failed);

    final again = await env.engine(json: true);
    await notifications.follow(again);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(plugin.shown, isEmpty);
  });

  test('texts in the language asked for', () {
    expect(
      HaulNotificationTexts.forLocale(const Locale('es')).channel,
      'Descargas',
    );
    expect(
      HaulNotificationTexts.forLocale(const Locale('fr')).channel,
      'Downloads',
    );
  });
}
