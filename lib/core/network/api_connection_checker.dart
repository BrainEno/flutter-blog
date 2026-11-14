import 'dart:async';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/network/connectivity_evidence.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;

/// A backend-specific, credential-free availability hint, not an authorization
/// decision. Concurrent callers share one probe. Only completed HTTP responses
/// are cached: a timeout is inconclusive, and definite failures are not cached,
/// so the next call can observe an immediately restored connection.
///
/// The positive TTL is deliberately short. A business request can still fail
/// within it; repositories must preserve their own transport-failure handling.
/// Only the origin and configured path prefix can contribute evidence. This
/// object is intended to be shared for the app lifetime for one fixed backend.
class ApiConnectionChecker implements ConnectionChecker, ConnectivityEvidence {
  ApiConnectionChecker(
    Uri baseUrl, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 3),
    this.successTtl = const Duration(seconds: 2),
    Duration Function()? elapsed,
  }) : _baseUrl = baseUrl,
       _prefix = baseUrl.path.replaceFirst(RegExp(r'/$'), ''),
       _healthUri = baseUrl.replace(
         path: '${baseUrl.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/health',
         query: null,
         fragment: null,
       ),
       _clientFactory = clientFactory ?? http.Client.new,
       _elapsed = elapsed ?? _monotonicClock() {
    if (timeout <= Duration.zero || successTtl < Duration.zero) {
      throw ArgumentError('Invalid connectivity probe duration');
    }
  }

  final Uri _baseUrl;
  final String _prefix;
  final Uri _healthUri;
  final http.Client Function() _clientFactory;
  final Duration Function() _elapsed;
  final Duration timeout;
  final Duration successTtl;
  http.Client? _client;
  Future<bool>? _inFlight;
  Duration? _lastResponse;
  int _evidenceVersion = 0;
  bool _lastEvidenceReachable = false;
  bool _closed = false;

  bool _belongsToBackend(Uri uri) =>
      uri.origin == _baseUrl.origin && uri.path.startsWith('$_prefix/api/v1/');

  bool get _fresh {
    final last = _lastResponse;
    if (last == null) return false;
    final age = _elapsed() - last;
    // A custom or platform clock moving backwards cannot extend a lease.
    return age >= Duration.zero && age < successTtl;
  }

  @override
  void recordResponse(Uri requestUri) {
    if (_closed || !_belongsToBackend(requestUri)) return;
    _evidenceVersion++;
    _lastEvidenceReachable = true;
    _lastResponse = _elapsed();
  }

  @override
  void recordTransportFailure(Uri requestUri) {
    if (_closed || !_belongsToBackend(requestUri)) return;
    _evidenceVersion++;
    _lastEvidenceReachable = false;
    _lastResponse = null;
  }

  @override
  Future<bool> get isConnected {
    if (_closed) return Future.value(false);
    if (_fresh) return Future.value(true);
    final current = _inFlight;
    if (current != null) return current;
    final completer = Completer<bool>();
    _inFlight = completer.future;
    final version = _evidenceVersion;
    unawaited(
      _probe(version).then(
        (value) {
          _inFlight = null;
          completer.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          _inFlight = null;
          completer.completeError(error, stack);
        },
      ),
    );
    return completer.future;
  }

  Future<bool> _probe(int version) async {
    final stopwatch = Stopwatch()..start();
    try {
      final client = _client ??= _clientFactory();
      // No credentials and no redirects. Every HTTP status, including 3xx,
      // establishes reachability without forwarding the probe to another host.
      final request = http.Request('GET', _healthUri)..followRedirects = false;
      final response = await client.send(request).timeout(timeout);
      await response.stream.drain<void>().timeout(timeout);
      if (_closed) return false;
      if (version != _evidenceVersion) return _lastEvidenceReachable;
      recordResponse(_healthUri);
      return true;
    } on TimeoutException {
      _resetClient();
      AppLogger.probeInconclusive(
        _healthUri.path,
        stopwatch.elapsedMilliseconds,
        timeout.inMilliseconds,
      );
      AppLogger.debug(
        'connectivity probe ${_healthUri.origin}${_healthUri.path} '
        'inconclusive after ${timeout.inMilliseconds}ms; the request decides',
      );
      if (_closed) return false;
      return version == _evidenceVersion ? true : _lastEvidenceReachable;
    } catch (error) {
      _resetClient();
      final errorType = '${error.runtimeType}';
      AppLogger.probeFailed(_healthUri.path, errorType);
      AppLogger.debug(
        'connectivity probe ${_healthUri.origin}${_healthUri.path} failed '
        '($errorType)',
      );
      if (_closed) return false;
      if (version != _evidenceVersion) return _lastEvidenceReachable;
      recordTransportFailure(_healthUri);
      return false;
    }
  }

  void _resetClient() {
    final previous = _client;
    _client = null;
    previous?.close();
  }

  /// Disposes the probe's own client only, never the business HTTP pool.
  /// An outstanding result cannot revive this checker after disposal.
  void close() {
    if (_closed) return;
    _closed = true;
    _lastResponse = null;
    _resetClient();
  }
}

/// Production callers share this backend-scoped checker in the composition root.
ConnectionChecker buildConnectionChecker(
  Uri apiBaseUrl, {
  http.Client Function()? clientFactory,
}) => ApiConnectionChecker(apiBaseUrl, clientFactory: clientFactory);

Duration Function() _monotonicClock() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}
