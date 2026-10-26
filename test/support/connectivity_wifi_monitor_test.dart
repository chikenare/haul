import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

class _FakeConnectivity implements Connectivity {
  List<ConnectivityResult> now = [ConnectivityResult.mobile];
  bool broken = false;
  final changes = StreamController<List<ConnectivityResult>>();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (broken) throw StateError('no plugin');
    return now;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => changes.stream;
}

void main() {
  test('Wi-Fi or a cable count; mobile data does not', () async {
    final connectivity = _FakeConnectivity();
    final monitor = ConnectivityWifiMonitor(connectivity);
    expect(await monitor.onWifi(), isFalse);
    connectivity.now = [ConnectivityResult.ethernet];
    expect(await monitor.onWifi(), isTrue);
  });

  test('changes, once each', () async {
    final connectivity = _FakeConnectivity();
    final seen = <bool>[];
    ConnectivityWifiMonitor(connectivity).changes.listen(seen.add);
    connectivity.changes
      ..add([ConnectivityResult.wifi])
      ..add([ConnectivityResult.wifi, ConnectivityResult.vpn])
      ..add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true, false]);
  });

  test('a reading that fails holds nothing back', () async {
    final connectivity = _FakeConnectivity()..broken = true;
    expect(await ConnectivityWifiMonitor(connectivity).onWifi(), isTrue);
  });
}
