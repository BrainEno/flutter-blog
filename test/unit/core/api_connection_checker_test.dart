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
    expect(
      AppLogger.diagnosticsReport(),
      contains('/api/v1/health'),
    );
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

  group('servesPrivateOrigin', () {
    test('recognises loopback, emulator and LAN origins', () {
      for (final origin in [
        'http://10.0.2.2:4000',
        'http://10.1.2.3',
        'http://127.0.0.1:3000',
        'http://localhost:3000',
        'http://[::1]:3000',
        'http://0.0.0.0:3000',
        'http://192.168.1.20:4000',
        'http://172.16.0.5:4000',
        'http://172.31.255.254:4000',
        'http://169.254.10.1:4000',
        'http://nas.local:4000',
      ]) {
        expect(
          ApiConnectionChecker.servesPrivateOrigin(Uri.parse(origin)),
          isTrue,
          reason: origin,
        );
      }
    });

    test('leaves public origins to the internet probe', () {
      for (final origin in [
        'https://api.belog.app',
        'https://example.com',
        'http://8.8.8.8',
        'http://11.0.0.1',
        'http://172.32.0.1',
        'http://172.15.0.1',
        'http://192.169.1.1',
        'http://not-an-ip.example',
        'http://1.2.3',
      ]) {
        expect(
          ApiConnectionChecker.servesPrivateOrigin(Uri.parse(origin)),
          isFalse,
          reason: origin,
        );
      }
    });
  });
}
