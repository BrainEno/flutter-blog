import 'package:belog/core/utils/app_logger.dart';

Future<T> retryOnConnectionClosed<T>(
  Future<T> Function() request, {
  int maxRetries = 3,
}) async {
  int retries = 0;
  while (true) {
    try {
      return await request();
    } catch (e) {
      if (e.toString().contains(
            'Connection closed before full header was received',
          ) &&
          retries < maxRetries) {
        retries++;
        AppLogger.debug('Connection closed; retry attempt $retries');
        await Future.delayed(Duration(seconds: 1));
      } else {
        rethrow;
      }
    }
  }
}
