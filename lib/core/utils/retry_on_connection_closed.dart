import 'dart:math' as math;

import 'package:belog/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;

/// Retries a request whose connection died before the server answered.
///
/// The transport error this targets (`Connection closed before full header
/// was received`) surfaces as an [http.ClientException] from the Dart SDK;
/// the message text is matched only as a last resort because it is not a
/// stable API. Retries are spaced with exponential backoff and jitter so a
/// fleet of clients cannot synchronize onto a recovering server.
///
/// [maxRetries] bounds the retry attempts; the initial try is not counted.
/// Every attempt is logged (debug builds) with the attempt number and the
/// error class, never the payload.
Future<T> retryOnConnectionClosed<T>(
  Future<T> Function() request, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(milliseconds: 500),
}) async {
  var retries = 0;
  while (true) {
    try {
      return await request();
    } catch (error) {
      if (!_isConnectionClosed(error) || retries >= maxRetries) {
        rethrow;
      }
      retries++;
      final backoff = initialDelay * math.pow(2, retries - 1);
      final delay = backoff + Duration(
        milliseconds: math.Random().nextInt(
          initialDelay.inMilliseconds + 1,
        ),
      );
      AppLogger.debug(
        'connection closed before response; retrying '
        '($retries/$maxRetries) after ${delay.inMilliseconds}ms '
        '(${error.runtimeType})',
      );
      await Future<void>.delayed(delay);
    }
  }
}

bool _isConnectionClosed(Object error) {
  // Preferred signal: the SDK's typed client exception.
  if (error is http.ClientException) {
    return true;
  }
  // Fallback for platforms/wrappers that re-wrap the transport error into
  // a different type while keeping the SDK's message text.
  return error.toString().contains(
        'Connection closed before full header was received',
      );
}
