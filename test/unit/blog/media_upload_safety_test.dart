import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockSessionManager extends Mock implements NowaveSessionManager {}

class RefreshingAuthenticator implements NowaveAuthenticator {
  String token = 'expired';
  int refreshes = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refresh() async {
    refreshes++;
    token = 'refreshed';
    return true;
  }
}

http.Response _createdAsset() => http.Response(
  jsonEncode({
    'data': {
      'id': 'asset-1',
      'contentType': 'image/webp',
      'byteSize': 3,
      'width': 1,
      'height': 1,
    },
  }),
  201,
);

NowaveApiClient _client(
  http.Client inner, {
  NowaveAuthenticator? authenticator,
}) => NowaveApiClient(
  baseUrl: Uri.parse('https://api.example.invalid'),
  authenticator: authenticator,
  httpClient: inner,
);

void main() {
  late Directory temporaryDirectory;
  late File image;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('belog-media-');
    image = File('${temporaryDirectory.path}/cover.png');
    await image.writeAsBytes([1, 2, 3]);
    AppLogger.clearDiagnostics();
  });

  tearDown(() async {
    AppLogger.clearDiagnostics();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'a lost cover response does not silently create a second asset',
    () async {
      var requests = 0;
      final httpClient = MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/me/media');
        expect(request.bodyBytes, [1, 2, 3]);
        expect(request.headers['content-type'], 'image/png');
        if (requests == 1) {
          // The first request may already have created the asset. A second
          // request would succeed, but would create another distinct asset.
          throw http.ClientException('private transport detail');
        }
        return _createdAsset();
      });
      final dataSource = BlogRemoteDataSourceImpl(_client(httpClient));

      await expectLater(
        dataSource.uploadBlogImage(image: image, mimeType: 'image/png'),
        throwsA(
          isA<ServerException>()
              .having((e) => e.kind, 'kind', FailureKind.network)
              .having((e) => e.message, 'message', isNot(contains('private'))),
        ),
      );
      expect(requests, 1);
      final diagnostics = AppLogger.diagnosticsReport();
      expect(
        diagnostics,
        contains('POST /api/v1/me/media unreachable (ClientException)'),
      );
      expect(diagnostics, isNot(contains('private transport detail')));
    },
  );

  test('a lost avatar response is also surfaced without a retry', () async {
    var requests = 0;
    final httpClient = MockClient((request) async {
      requests++;
      if (requests == 1) {
        throw http.ClientException('private transport detail');
      }
      return _createdAsset();
    });
    final dataSource = UserRemoteDataSourceImpl(
      _client(httpClient),
      MockSessionManager(),
    );

    await expectLater(
      dataSource.uploadAvatar(image: image, mimeType: 'image/png'),
      throwsA(
        isA<ServerException>().having(
          (e) => e.kind,
          'kind',
          FailureKind.network,
        ),
      ),
    );
    expect(requests, 1);
  });

  test('a timed-out upload is surfaced without another POST', () async {
    var requests = 0;
    final httpClient = MockClient((request) async {
      requests++;
      throw TimeoutException('private timeout detail');
    });
    final dataSource = BlogRemoteDataSourceImpl(_client(httpClient));

    await expectLater(
      dataSource.uploadBlogImage(image: image),
      throwsA(
        isA<ServerException>().having(
          (e) => e.kind,
          'kind',
          FailureKind.timeout,
        ),
      ),
    );
    expect(requests, 1);
    expect(
      AppLogger.diagnosticsReport(),
      isNot(contains('private timeout detail')),
    );
  });

  test(
    'a successful cover upload still returns the versioned media URL',
    () async {
      var requests = 0;
      final httpClient = MockClient((request) async {
        requests++;
        expect(request.headers['content-type'], 'image/png');
        return _createdAsset();
      });
      final dataSource = BlogRemoteDataSourceImpl(_client(httpClient));

      expect(
        await dataSource.uploadBlogImage(image: image, mimeType: 'image/png'),
        'https://api.example.invalid/api/v1/media/asset-1',
      );
      expect(requests, 1);
    },
  );

  test(
    'a successful avatar upload still returns the versioned media URL',
    () async {
      var requests = 0;
      final httpClient = MockClient((request) async {
        requests++;
        return _createdAsset();
      });
      final dataSource = UserRemoteDataSourceImpl(
        _client(httpClient),
        MockSessionManager(),
      );

      expect(
        await dataSource.uploadAvatar(image: image, mimeType: 'image/png'),
        'https://api.example.invalid/api/v1/media/asset-1',
      );
      expect(requests, 1);
    },
  );

  test('an explicit 401 still permits one authenticated replay', () async {
    final authenticator = RefreshingAuthenticator();
    final seenTokens = <String?>[];
    final httpClient = MockClient((request) async {
      seenTokens.add(request.headers['authorization']);
      if (seenTokens.length == 1) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHENTICATED', 'message': 'expired'},
          }),
          401,
        );
      }
      expect(request.bodyBytes, [1, 2, 3]);
      return _createdAsset();
    });
    final dataSource = BlogRemoteDataSourceImpl(
      _client(httpClient, authenticator: authenticator),
    );

    expect(
      await dataSource.uploadBlogImage(image: image),
      'https://api.example.invalid/api/v1/media/asset-1',
    );
    expect(authenticator.refreshes, 1);
    expect(seenTokens, ['Bearer expired', 'Bearer refreshed']);
  });
}
