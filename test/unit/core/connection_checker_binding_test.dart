import 'dart:io';

import 'package:belog/core/network/api_connection_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('public and private origins both probe the API itself', () async {
    for (final origin in <String>[
      'https://api.example.invalid',
      'http://10.0.2.2:4000',
    ]) {
      final requests = <http.Request>[];
      final checker = buildConnectionChecker(
        Uri.parse(origin),
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      );

      expect(await checker.isConnected, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.url.origin, Uri.parse(origin).origin);
      expect(requests.single.url.path, endsWith('/api/v1/health'));
      // The probe must never carry credentials.
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      expect(requests.single.headers.containsKey('cookie'), isFalse);
    }
  });

  test('no host other than the API is contacted', () async {
    // A release build used to consult a public-internet probe first, so a
    // blocked public internet turned a reachable backend into a pre-flight
    // "no network" without sending the request (issue #105).
    final requests = <http.Request>[];
    final checker = buildConnectionChecker(
      Uri.parse('https://blog.example.invalid'),
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      }),
    );

    expect(await checker.isConnected, isTrue);
    expect(requests.map((request) => request.url.host).toSet(), {
      'blog.example.invalid',
    });
  });

  test('an unreachable API still reports offline', () async {
    // Definite transport failures must keep the cached/offline fallbacks and
    // the "no network" failures of the real repositories working.
    final checker = buildConnectionChecker(
      Uri.parse('https://blog.example.invalid'),
      clientFactory: () =>
          MockClient((_) async => throw const SocketException('lost')),
    );

    expect(await checker.isConnected, isFalse);
  });
}
