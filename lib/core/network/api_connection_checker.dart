import 'dart:async';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;

/// Connectivity probe that asks the configured backend itself, not the
/// public internet.
///
/// This is the only probe wired into the app's request path, in every build
/// mode and for every origin class (see [buildConnectionChecker]): a backend
/// on the host/LAN, behind a blocked public internet, or in an offline demo
/// environment is exactly the case the public-internet probe got wrong. An
/// HTTP error response still means the server was reached; the real request
/// must surface its own error rather than disguising it as an offline-cache
/// success.
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

  /// True when [url] addresses a loopback, link-local or RFC 1918 host.
  ///
  /// Those origins - the Android emulator alias `10.0.2.2`, `localhost`, a
  /// machine on the LAN, `*.local` - must be judged by probing the API
  /// itself. The public-internet probe answers a different question and
  /// reports "offline" whenever it cannot reach its own public endpoints,
  /// even though the development backend is right there; that mismatch is
  /// what turns a reachable local API into a bogus "无法连接到网络" on login.
  static bool servesPrivateOrigin(Uri url) {
    final host = url.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' || host == '::1' || host == '0.0.0.0') return true;
    if (host.endsWith('.local')) return true;
    final octets = host.split('.');
    if (octets.length != 4) return false;
    final parts = <int>[];
    for (final octet in octets) {
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return false;
      parts.add(value);
    }
    if (parts[0] == 10 || parts[0] == 127) return true;
    if (parts[0] == 169 && parts[1] == 254) return true;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    return parts[0] == 192 && parts[1] == 168;
  }

  /// Whether the backend can be reached.
  ///
  /// Only a *definite* transport failure (refused, no route, blocked
  /// cleartext) reports `false`. A probe timeout is **inconclusive**: a cold
  /// development server, a paused debugger or a slow proxy can exceed the
  /// short probe budget and still answer the real request, whose own budget
  /// is far longer. Reporting "offline" there would block a perfectly
  /// healthy login, so the request gets to decide and surface its own error.
  @override
  Future<bool> get isConnected async {
    http.Client? client;
    final stopwatch = Stopwatch()..start();
    try {
      client = _clientFactory();
      await client.get(_healthUri).timeout(timeout);
      return true;
    } on TimeoutException {
      AppLogger.probeInconclusive(
        _healthUri.path,
        stopwatch.elapsedMilliseconds,
        timeout.inMilliseconds,
      );
      AppLogger.debug(
        'connectivity probe ${_healthUri.origin}${_healthUri.path} '
        'inconclusive after ${timeout.inMilliseconds}ms; the request decides',
      );
      return true;
    } catch (error) {
      // Every repository turns this false into a user-facing "no network"
      // message, so the reason (refused, DNS, blocked cleartext) must not
      // vanish: record the probe target and the error type.
      final errorType = '${error.runtimeType}';
      AppLogger.probeFailed(_healthUri.path, errorType);
      AppLogger.debug(
        'connectivity probe ${_healthUri.origin}${_healthUri.path} failed '
        '($errorType)',
      );
      return false;
    } finally {
      client?.close();
    }
  }
}

/// Builds the [ConnectionChecker] every repository gates its requests on.
///
/// Deliberately unconditional: build mode, origin class and the
/// `BELOG_DEV_BACKEND_CHECK` define no longer decide it. A public-internet
/// probe is not consulted at all, so a reachable API is never reported as
/// offline before the request is sent (issue #105).
ConnectionChecker buildConnectionChecker(
  Uri apiBaseUrl, {
  http.Client Function()? clientFactory,
}) => ApiConnectionChecker(apiBaseUrl, clientFactory: clientFactory);
