import 'package:belog/core/network/connection_checker.dart';
import 'package:http/http.dart' as http;

/// Debug-only connectivity probe for a development backend.
///
/// Unlike the public-internet probe this can detect a reachable API on the
/// host/LAN without internet access. An HTTP error response still means the
/// server was reached; the real request must surface its own error rather
/// than disguising it as an offline-cache success.
class ApiConnectionChecker implements ConnectionChecker {
  ApiConnectionChecker(
    Uri baseUrl, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 3),
  }) : _healthUri = baseUrl.replace(
         path: '${baseUrl.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/health',
         query: null,
         fragment: null,
       ),
       _clientFactory = clientFactory ?? http.Client.new;

  final Uri _healthUri;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  @override
  Future<bool> get isConnected async {
    http.Client? client;
    try {
      client = _clientFactory();
      await client.get(_healthUri).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      client?.close();
    }
  }
}
