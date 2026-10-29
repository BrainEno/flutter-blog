import 'dart:async';

import 'package:belog/features/auth/auth_link_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeDeepLinkSource implements DeepLinkSource {
  FakeDeepLinkSource({this.initial});

  final Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get links => controller.stream;
}

Session _session() => Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: User(
    id: 'u1',
    appMetadata: {},
    userMetadata: {},
    aud: '',
    createdAt: '2024-01-01T00:00:00Z',
  ),
);

void main() {
  late FakeDeepLinkSource links;
  late List<(AuthLinkResult, String)> results;
  late Completer<({AuthSessionUrlResponse response, AuthChangeEvent? event})>
  nextResolution;

  AuthLinkHandler buildHandler() => AuthLinkHandler(
    links: links,
    resolveCallbackUrl: (url) => nextResolution.future,
    onResult: (result, message) => results.add((result, message)),
  );

  setUp(() {
    links = FakeDeepLinkSource();
    results = [];
    nextResolution =
        Completer<
          ({AuthSessionUrlResponse response, AuthChangeEvent? event})
        >();
  });

  tearDown(() => links.controller.close());

  test('handles the initial (cold start) link', () async {
    links = FakeDeepLinkSource(
      initial: Uri.parse('belog://auth-callback?code=abc'),
    );
    final handler = buildHandler();
    await handler.start();

    nextResolution.complete((
      response: AuthSessionUrlResponse(session: _session(), redirectType: null),
      event: AuthChangeEvent.signedIn,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(results.single.$1, AuthLinkResult.accepted);
    expect(results.single.$2, contains('邮箱验证成功'));
    await handler.dispose();
  });

  test('a password-recovery link is identified as such', () async {
    final handler = buildHandler();
    await handler.start();

    links.controller.add(Uri.parse('belog://auth-callback?code=abc'));
    nextResolution.complete((
      response: AuthSessionUrlResponse(session: _session(), redirectType: null),
      event: AuthChangeEvent.passwordRecovery,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(results.single.$1, AuthLinkResult.accepted);
    expect(results.single.$2, contains('设置新密码'));
    await handler.dispose();
  });

  test(
    'an expired/invalid link (resolver throws) is rejected with guidance',
    () async {
      final handler = buildHandler();
      await handler.start();

      links.controller.add(Uri.parse('belog://auth-callback?code=expired'));
      nextResolution.completeError(
        AuthException(
          'Invalid request: both auth code and code verifier are '
          'expired',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(results.single.$1, AuthLinkResult.rejected);
      expect(results.single.$2, contains('重新获取邮件'));
      await handler.dispose();
    },
  );

  test('a resolver failure is rejected, not swallowed', () async {
    final handler = buildHandler();
    await handler.start();

    links.controller.add(Uri.parse('belog://auth-callback?code=abc'));
    nextResolution.completeError(StateError('resolver exploded'));
    await Future<void>.delayed(Duration.zero);

    expect(results.single.$1, AuthLinkResult.rejected);
    await handler.dispose();
  });

  test('links with a foreign scheme are ignored', () async {
    final handler = buildHandler();
    await handler.start();

    links.controller.add(Uri.parse('https://example.com/callback?code=abc'));
    await Future<void>.delayed(Duration.zero);

    expect(results, isEmpty);
    expect(nextResolution.isCompleted, isFalse);
    await handler.dispose();
  });

  test('start() is idempotent', () async {
    final handler = buildHandler();
    await handler.start();
    await handler.start();

    links.controller.add(Uri.parse('belog://auth-callback?code=abc'));
    nextResolution.complete((
      response: AuthSessionUrlResponse(session: _session(), redirectType: null),
      event: AuthChangeEvent.signedIn,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(results, hasLength(1));
    await handler.dispose();
  });
}
