import 'package:connectivity_plus/connectivity_plus.dart';

abstract final class ConnectivityUtil {
  static Future<bool> hasNetworkConnection() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }
}
