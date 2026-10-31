import 'dart:async';
import 'dart:io';

import 'package:belog/core/network/api_connection_checker.dart';
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

  test(
    'connection errors and timeouts report an unavailable backend',
    () async {
      final disconnected = ApiConnectionChecker(
        Uri.parse('http://localhost:3000'),
        clientFactory: () =>
            MockClient((_) async => throw const SocketException('lost')),
      );
      final delayed = ApiConnectionChecker(
        Uri.parse('http://localhost:3000'),
        timeout: const Duration(milliseconds: 1),
        clientFactory: () =>
            MockClient((_) => Completer<http.Response>().future),
      );
      expect(await disconnected.isConnected, isFalse);
      expect(await delayed.isConnected, isFalse);
    },
  );
}
