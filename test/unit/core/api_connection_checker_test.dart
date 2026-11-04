import 'dart:async';
import 'dart:io';

import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('probes the configured backend without credentials', () async {
    late Uri requested;
    late Map<String, String> headers;
    final checker = ApiConnectionChecker(
      Uri.parse('http://10.0.2.2:3000/prefix/'),
      clientFactory: () => MockClient((request) async {
        requested = request.url;
        headers = request.headers;
        return http.Response('unavailable', 503);
      }),
    );

    // Even a server error must be passed on to the actual API request.
    expect(await checker.isConnected, isTrue);
    expect(requested.toString(), 'http://10.0.2.2:3000/prefix/api/v1/health');
    expect(headers.containsKey('authorization'), isFalse);
  });

  test('a definite connection error reports an unavailable backend', () async {
    final disconnected = ApiConnectionChecker(
      Uri.parse('http://localhost:3000'),
      clientFactory: () =>
          MockClient((_) async => throw const SocketException('lost')),
    );

    expect(await disconnected.isConnected, isFalse);
  });

  test('a slow probe is inconclusive, never a blocked login', () async {
    AppLogger.clearDiagnostics();
    addTearDown(AppLogger.clearDiagnostics);
    final delayed = ApiConnectionChecker(
      Uri.parse('http://10.0.2.2:4000'),
      timeout: const Duration(milliseconds: 1),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );

    // A cold development server can exceed the probe budget and still answer
    // the real request, whose own budget is far longer.
    expect(await delayed.isConnected, isTrue);
    expect(
      AppLogger.diagnosticsReport(),
      contains('inconclusive (TimeoutException'),
    );
    expect(AppLogger.diagnosticsReport(), contains('/api/v1/health'));
  });

  test('a failed probe is recorded, never a silent false', () async {
    AppLogger.clearDiagnostics();
    addTearDown(AppLogger.clearDiagnostics);
    final checker = ApiConnectionChecker(
      Uri.parse('http://10.0.2.2:4000'),
      clientFactory: () =>
          MockClient((_) async => throw const SocketException('refused')),
    );

    expect(await checker.isConnected, isFalse);
    // Every repository turns this false into "no network"; the buffer has to
    // say which probe failed and how, or the report is undiagnosable.
    expect(
      AppLogger.diagnosticsReport(),
      contains('probe GET /api/v1/health failed (SocketException)'),
    );
  });
}
