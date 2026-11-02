import 'package:belog/core/utils/app_logger.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

abstract interface class ConnectionChecker {
  Future<bool> get isConnected;
}

class ConnectionCheckerImpl implements ConnectionChecker {
  final InternetConnection internetConnection;

  ConnectionCheckerImpl(this.internetConnection);

  /// Public-internet reachability only: it answers "can this device reach the
  /// probe's public endpoints", which is the wrong question for a LAN or
  /// loopback API (that case is handled by `ApiConnectionChecker`).
  ///
  /// A false result is recorded in the diagnostics buffer, so a "no network"
  /// report shows whether this probe or the API itself failed.
  @override
  Future<bool> get isConnected async {
    try {
      final connected = await internetConnection.hasInternetAccess;
      if (!connected) AppLogger.connectivityOffline();
      return connected;
    } catch (error) {
      // The probe itself must not turn a login attempt into an unknown
      // failure: report offline and keep the reason in the diagnostics.
      AppLogger.connectivityOffline();
      AppLogger.debug('internet probe failed: ${error.runtimeType}');
      return false;
    }
  }
}
