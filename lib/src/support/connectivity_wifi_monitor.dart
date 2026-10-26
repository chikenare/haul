import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:haul/src/engine/extension_points.dart';

/// [WifiMonitor] over connectivity_plus. A cable counts as Wi-Fi: what
/// matters is not spending mobile data. When the platform cannot say, it
/// answers Wi-Fi — a reading that fails never holds a download back.
class ConnectivityWifiMonitor implements WifiMonitor {
  ConnectivityWifiMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> onWifi() async {
    try {
      return _unmetered(await _connectivity.checkConnectivity());
    } on Object {
      return true;
    }
  }

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged
      .map(_unmetered)
      .handleError((Object _) {})
      .distinct();

  static bool _unmetered(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);
}
