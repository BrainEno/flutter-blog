import 'dart:convert';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/data/views/nowave_article_view_recorder.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/views/article_view_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Identity
    implements
        NowaveSessionIdentity,
        NowaveViewerAuthenticator,
        NowaveProactiveAuthenticator {
  @override
  String? activeUserId;
  @override
  String? accessToken;
  @override
  int sessionGeneration = 1;
  @override
  Stream<void> get identityChanges => const Stream.empty();
  int refreshes = 0;
  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }

  @override
  Future<bool> ensureFreshAccess() async {
    refreshes++;
    return true;
  }
}

Blog _blog({String locale = 'en', bool draft = false, String id = 'story'}) =>
    Blog(
      id: id,
      title: 'Story',
      content: 'Text',
      posterId: 'writer',
      imageUrl: '',
      tags: [],
      updatedAt: DateTime.utc(2025),
      locale: locale,
      isDraft: draft,
    );

void main() {
  late _Identity identity;
  late List<http.Request> requests;
  late MockClient transport;
  late RecordArticleView recorder;
  setUp(() {
    identity = _Identity();
    requests = [];
    transport = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'data': {'counted': true, 'viewCount': 3},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    recorder = RecordArticleView(
      NowaveArticleViewRecorder(
        client: NowaveApiClient(
          baseUrl: Uri.parse('https://example.invalid'),
          authenticator: identity,
          httpClient: transport,
        ),
        identity: identity,
      ),
    );
  });
  tearDown(() => transport.close());

  test(
    'anonymous beacon uses article locale without bearer or redirects',
    () async {
      await recorder.prepare(_blog())!();
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/articles/story/views');
      expect(requests.single.url.queryParameters, {'locale': 'en'});
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      expect(requests.single.followRedirects, isFalse);
      expect(identity.refreshes, 0);
    },
  );
  test(
    'authenticated beacon does not refresh and carries the captured viewer',
    () async {
      identity.activeUserId = 'reader';
      identity.accessToken = 'token';
      await recorder.prepare(_blog())!();
      expect(requests.single.headers['authorization'], 'Bearer token');
      expect(identity.refreshes, 0);
    },
  );
  test('identity switch before paint drops the prepared beacon', () async {
    identity.activeUserId = 'a';
    identity.accessToken = 'a-token';
    final operation = recorder.prepare(_blog())!;
    identity.activeUserId = 'b';
    identity.accessToken = 'b-token';
    identity.sessionGeneration++;
    await operation();
    expect(requests, isEmpty);
  });
  test(
    'sign-in after anonymous preparation does not count against new account',
    () async {
      final operation = recorder.prepare(_blog())!;
      identity.activeUserId = 'a';
      identity.accessToken = 'a-token';
      identity.sessionGeneration++;
      await operation();
      expect(requests, isEmpty);
    },
  );
  test('unknown locale, empty slug and drafts never prepare requests', () {
    expect(recorder.prepare(_blog(locale: '')), isNull);
    expect(recorder.prepare(_blog(draft: true)), isNull);
    expect(recorder.prepare(_blog(id: '')), isNull);
    expect(recorder.prepare(_blog(id: '../private')), isNull);
    expect(recorder.prepare(_blog(id: 'a/b')), isNull);
    expect(requests, isEmpty);
  });
}
