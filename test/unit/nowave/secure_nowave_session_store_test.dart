import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/secure_nowave_session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock
    implements FlutterSecureStorage {}

NowaveSessionData _session() => NowaveSessionData(
  userId: 'u1',
  email: 'user@example.invalid',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

void main() {
  group('SecureNowaveSessionStore', () {
    test('read returns the decoded session', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.read(key: 'nowave_session_v1')).thenAnswer(
        (_) async => NowaveSessionManager.encodeSession(_session()),
      );
      final store = SecureNowaveSessionStore(storage);

      final session = await store.read();

      expect(session?.accessToken, 'access-1');
      expect(session?.refreshToken, 'refresh-1');
    });

    test('read of corrupt or missing data yields null', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.read(key: 'nowave_session_v1'))
          .thenAnswer((_) async => 'not json {');
      final store = SecureNowaveSessionStore(storage);

      expect(await store.read(), isNull);
    });

    test('write encodes the session under the fixed key', () async {
      final storage = MockFlutterSecureStorage();
      when(
        () => storage.write(
          key: 'nowave_session_v1',
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      final store = SecureNowaveSessionStore(storage);

      await store.write(_session());

      verify(
        () => storage.write(
          key: 'nowave_session_v1',
          value: any(
            named: 'value',
            that: contains('"accessToken":"access-1"'),
          ),
        ),
      ).called(1);
    });

    test('clear deletes the fixed key', () async {
      final storage = MockFlutterSecureStorage();
      when(() => storage.delete(key: 'nowave_session_v1'))
          .thenAnswer((_) async {});
      final store = SecureNowaveSessionStore(storage);

      await store.clear();

      verify(() => storage.delete(key: 'nowave_session_v1')).called(1);
    });
  });
}
