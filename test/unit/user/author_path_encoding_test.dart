import 'dart:convert';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'opening and following a listed author keeps the ID in one path segment',
    () async {
      const id = 'name/with?reserved#%中';
      final seen = <http.Request>[];
      final client = NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/articles')
                  ? []
                  : {'userId': id, 'updatedAt': '2026-01-01T00:00:00Z'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final author = AuthorRemoteDataSourceImpl(client);
      final blogs = BlogRemoteDataSourceImpl(client);
      await author.getAuthorProfile(id);
      await author.followAuthor(id);
      await author.unfollowAuthor(id);
      await blogs.getBlogsByPosterId(id);
      expect(seen.map((request) => request.method), [
        'GET',
        'POST',
        'DELETE',
        'GET',
      ]);
      expect(seen[0].url.pathSegments, ['api', 'v1', 'authors', id]);
      expect(seen[1].url.pathSegments, ['api', 'v1', 'users', id, 'follow']);
      expect(seen[2].url.pathSegments, ['api', 'v1', 'users', id, 'follow']);
      expect(seen[3].url.pathSegments, [
        'api',
        'v1',
        'authors',
        id,
        'articles',
      ]);
    },
  );
}
