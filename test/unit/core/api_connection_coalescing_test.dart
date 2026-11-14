import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _base = Uri.parse('https://backend.example.invalid/prefix');
final _health = Uri.parse(
  'https://backend.example.invalid/prefix/api/v1/health',
);
final _business = Uri.parse(
  'https://backend.example.invalid/prefix/api/v1/articles',
);

class _Clock {
  Duration value = Duration.zero;
  Duration call() => value;
  void advance(Duration duration) => value += duration;
}

typedef _Handler =
    Future<http.StreamedResponse> Function(http.BaseRequest request);

class _Client extends http.BaseClient {
  _Client(this.handler);
  final _Handler handler;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  int closeCount = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {
    closed = true;
    closeCount++;
  }
}

http.StreamedResponse _response(int status, [String body = '']) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status);

void main() {
  group('backend connectivity evidence', () {
    late _Clock clock;
    late _Client probe;
    late ApiConnectionChecker checker;
    setUp(() {
      clock = _Clock();
      probe = _Client((_) async => _response(200));
      checker = ApiConnectionChecker(
        _base,
        clientFactory: () => probe,
        elapsed: clock.call,
      );
    });
    tearDown(() => checker.close());

    test('parallel requests share a single in-flight probe', () async {
      final gate = Completer<http.StreamedResponse>();
      final delayed = _Client((_) => gate.future);
      final local = ApiConnectionChecker(
        _base,
        clientFactory: () => delayed,
        elapsed: clock.call,
      );
      addTearDown(local.close);
      final results = List.generate(40, (_) => local.isConnected);
      expect(delayed.requests, hasLength(1));
      expect(delayed.requests.single.url, _health);
      expect(delayed.requests.single.followRedirects, isFalse);
      expect(delayed.requests.single.headers, isEmpty);
      gate.complete(_response(200));
      expect(await Future.wait(results), everyElement(isTrue));
      expect(await local.isConnected, isTrue);
      expect(delayed.requests, hasLength(1));
    });

    test('successful probe caches until exact TTL boundary', () async {
      expect(await checker.isConnected, isTrue);
      clock.advance(const Duration(milliseconds: 1999));
      expect(await checker.isConnected, isTrue);
      expect(probe.requests, hasLength(1));
      clock.advance(const Duration(milliseconds: 1));
      expect(await checker.isConnected, isTrue);
      expect(probe.requests, hasLength(2));
      expect(probe.closeCount, 0);
    });

    test('pooled probe client is reused across expired leases', () async {
      var clients = 0;
      final local = ApiConnectionChecker(
        _base,
        elapsed: clock.call,
        clientFactory: () {
          clients++;
          return probe;
        },
      );
      addTearDown(local.close);
      for (var i = 0; i < 5; i++) {
        expect(await local.isConnected, isTrue);
        clock.advance(const Duration(seconds: 2));
      }
      expect(clients, 1);
      expect(probe.requests, hasLength(5));
    });

    test('business response refreshes lease without a health call', () async {
      checker.recordResponse(_business);
      expect(await checker.isConnected, isTrue);
      clock.advance(const Duration(seconds: 1));
      checker.recordResponse(_business);
      clock.advance(const Duration(seconds: 1));
      expect(await checker.isConnected, isTrue);
      expect(probe.requests, isEmpty);
      clock.advance(const Duration(seconds: 1));
      expect(await checker.isConnected, isTrue);
      expect(probe.requests, hasLength(1));
    });

    test(
      'unrelated scheme, port, host and prefix cannot set evidence',
      () async {
        for (final url in [
          'http://backend.example.invalid/prefix/api/v1/articles',
          'https://backend.example.invalid:444/prefix/api/v1/articles',
          'https://other.example.invalid/prefix/api/v1/articles',
          'https://backend.example.invalid/prefix2/api/v1/articles',
          'https://backend.example.invalid/api/v1/articles',
        ]) {
          checker.recordResponse(Uri.parse(url));
        }
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, hasLength(1));
      },
    );

    test(
      'failure evidence invalidates success, but foreign failure does not',
      () async {
        checker.recordResponse(_business);
        checker.recordTransportFailure(
          Uri.parse('https://other.example.invalid/prefix/api/v1/articles'),
        );
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, isEmpty);
        checker.recordTransportFailure(_business);
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, hasLength(1));
      },
    );

    test(
      'monotonic clock rollback never extends successful evidence',
      () async {
        clock.value = const Duration(seconds: 10);
        checker.recordResponse(_business);
        clock.value = const Duration(seconds: 9);
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, hasLength(1));
      },
    );

    test('zero TTL disables caching without disabling single flight', () async {
      final local = ApiConnectionChecker(
        _base,
        clientFactory: () => probe,
        successTtl: Duration.zero,
        elapsed: clock.call,
      );
      addTearDown(local.close);
      expect(await local.isConnected, isTrue);
      expect(await local.isConnected, isTrue);
      expect(probe.requests, hasLength(2));
    });

    for (final status in [200, 301, 302, 401, 403, 404, 500, 503]) {
      test(
        'HTTP $status is reachability, not authentication or health success',
        () async {
          final responseClient = _Client((_) async => _response(status));
          final local = ApiConnectionChecker(
            _base,
            clientFactory: () => responseClient,
            elapsed: clock.call,
          );
          addTearDown(local.close);
          expect(await local.isConnected, isTrue);
          expect(await local.isConnected, isTrue);
          expect(responseClient.requests, hasLength(1));
          expect(responseClient.requests.single.followRedirects, isFalse);
        },
      );
    }

    test(
      'definite failure is shared but not cached, permitting fast recovery',
      () async {
        final gate = Completer<http.StreamedResponse>();
        final broken = _Client((_) => gate.future);
        final repaired = _Client((_) async => _response(200));
        var created = 0;
        final local = ApiConnectionChecker(
          _base,
          clientFactory: () => created++ == 0 ? broken : repaired,
          elapsed: clock.call,
        );
        addTearDown(local.close);
        final attempts = List.generate(8, (_) => local.isConnected);
        gate.completeError(const SocketException('offline'));
        expect(await Future.wait(attempts), everyElement(isFalse));
        expect(broken.closeCount, 1);
        expect(await local.isConnected, isTrue);
        expect(created, 2);
        expect(repaired.requests, hasLength(1));
      },
    );

    test(
      'timeout is inconclusive and never cached as successful evidence',
      () async {
        final hanging = _Client(
          (_) => Completer<http.StreamedResponse>().future,
        );
        final repaired = _Client((_) async => _response(200));
        var count = 0;
        final local = ApiConnectionChecker(
          _base,
          timeout: const Duration(milliseconds: 5),
          clientFactory: () => count++ == 0 ? hanging : repaired,
          elapsed: clock.call,
        );
        addTearDown(local.close);
        expect(await local.isConnected, isTrue);
        expect(hanging.closeCount, 1);
        expect(await local.isConnected, isTrue);
        expect(repaired.requests, hasLength(1));
      },
    );

    test(
      'stalled response body is bounded and pooled client is replaced',
      () async {
        // Use a stream that never closes rather than an empty completed body.
        final body = StreamController<List<int>>();
        final delayed = _Client(
          (_) async => http.StreamedResponse(body.stream, 200),
        );
        final local = ApiConnectionChecker(
          _base,
          timeout: const Duration(milliseconds: 5),
          clientFactory: () => delayed,
          elapsed: clock.call,
        );
        addTearDown(() async {
          local.close();
          await body.close();
        });
        expect(await local.isConnected, isTrue);
        expect(delayed.closeCount, 1);
      },
    );

    test('newer business success beats older failing probe', () async {
      final gate = Completer<http.StreamedResponse>();
      final delayed = _Client((_) => gate.future);
      final local = ApiConnectionChecker(
        _base,
        clientFactory: () => delayed,
        elapsed: clock.call,
      );
      addTearDown(local.close);
      final pending = local.isConnected;
      local.recordResponse(_business);
      gate.completeError(const SocketException('old failure'));
      expect(await pending, isTrue);
      expect(await local.isConnected, isTrue);
      expect(delayed.requests, hasLength(1));
    });

    test('newer business failure beats an older successful probe', () async {
      final gate = Completer<http.StreamedResponse>();
      final delayed = _Client((_) => gate.future);
      final local = ApiConnectionChecker(
        _base,
        clientFactory: () => delayed,
        elapsed: clock.call,
      );
      addTearDown(local.close);
      final pending = local.isConnected;
      local.recordTransportFailure(_business);
      gate.complete(_response(200));
      expect(await pending, isFalse);
      expect(delayed.requests, hasLength(1));
    });

    test(
      'closing is idempotent and late success cannot reopen the checker',
      () async {
        final gate = Completer<http.StreamedResponse>();
        final delayed = _Client((_) => gate.future);
        final local = ApiConnectionChecker(
          _base,
          clientFactory: () => delayed,
          elapsed: clock.call,
        );
        final pending = local.isConnected;
        local.close();
        local.close();
        gate.complete(_response(200));
        expect(await pending, isFalse);
        expect(await local.isConnected, isFalse);
        local.recordResponse(_business);
        expect(await local.isConnected, isFalse);
        expect(delayed.closeCount, 1);
      },
    );

    test('backend instances do not share leases or clients', () async {
      final otherProbe = _Client((_) async => _response(200));
      final other = ApiConnectionChecker(
        Uri.parse('https://other.example.invalid'),
        clientFactory: () => otherProbe,
        elapsed: clock.call,
      );
      addTearDown(other.close);
      checker.recordResponse(_business);
      expect(await checker.isConnected, isTrue);
      expect(await other.isConnected, isTrue);
      expect(probe.requests, isEmpty);
      expect(otherProbe.requests.single.url.host, 'other.example.invalid');
    });

    test('invalid timing configuration is rejected', () {
      expect(
        () => ApiConnectionChecker(_base, timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => ApiConnectionChecker(
          _base,
          successTtl: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('business transport integration', () {
    late _Clock clock;
    late _Client probe;
    late ApiConnectionChecker checker;
    setUp(() {
      clock = _Clock();
      probe = _Client((_) async => _response(200));
      checker = ApiConnectionChecker(
        _base,
        clientFactory: () => probe,
        elapsed: clock.call,
      );
    });
    tearDown(() => checker.close());

    test(
      'successful API response supplies a lease without credentials in probe',
      () async {
        final transport = _Client(
          (_) async => _response(200, '{"data":{"ok":true}}'),
        );
        addTearDown(transport.close);
        final api = NowaveApiClient(
          baseUrl: _base,
          httpClient: transport,
          connectivityEvidence: checker,
        );
        final data = await api.getJson('/articles');
        expect(data['ok'], isTrue);
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, isEmpty);
        expect(transport.requests.single.url, _business);
      },
    );

    test(
      'HTTP error reaches backend and does not masquerade as offline',
      () async {
        final transport = _Client(
          (_) async => _response(
            403,
            '{"error":{"code":"FORBIDDEN","message":"denied"}}',
          ),
        );
        addTearDown(transport.close);
        final api = NowaveApiClient(
          baseUrl: _base,
          httpClient: transport,
          connectivityEvidence: checker,
        );
        await expectLater(
          api.getJson('/articles'),
          throwsA(isA<NowaveApiException>()),
        );
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, isEmpty);
      },
    );

    for (final error in [
      const SocketException('offline'),
      const HttpException('offline'),
      http.ClientException('offline'),
    ]) {
      test(
        'business ${error.runtimeType} invalidates positive evidence',
        () async {
          checker.recordResponse(_business);
          final transport = _Client((_) async => throw error);
          addTearDown(transport.close);
          final api = NowaveApiClient(
            baseUrl: _base,
            httpClient: transport,
            connectivityEvidence: checker,
          );
          await expectLater(api.getJson('/articles'), throwsA(same(error)));
          expect(await checker.isConnected, isTrue);
          expect(probe.requests, hasLength(1));
        },
      );
    }

    test(
      'business timeout does not become a definitive offline signal',
      () async {
        final transport = _Client(
          (_) => Completer<http.StreamedResponse>().future,
        );
        addTearDown(transport.close);
        final api = NowaveApiClient(
          baseUrl: _base,
          httpClient: transport,
          connectivityEvidence: checker,
          timeout: const Duration(milliseconds: 5),
        );
        checker.recordResponse(_business);
        await expectLater(
          api.getJson('/articles'),
          throwsA(isA<TimeoutException>()),
        );
        expect(await checker.isConnected, isTrue);
        expect(probe.requests, isEmpty);
      },
    );
  });
}
