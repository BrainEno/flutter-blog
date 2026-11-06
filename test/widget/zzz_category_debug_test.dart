import 'dart:convert';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/category_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _Connection extends Mock implements ConnectionChecker {}

Map<String, dynamic> _row({String slug = 'essay-1a2b'}) => {
  'id': 'tax-1',
  'kind': 'category',
  'slug': slug,
  'name': '随笔',
  'description': '短小的日常记录',
  'locale': 'zh-CN',
};

http.Response _data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);

void main() {
  Future<void> probe(String label, Object? payload) async {
    final client = MockClient((_) async => _data(payload));
    final connection = _Connection();
    when(() => connection.isConnected).thenAnswer((_) async => true);
    final repository = CategoryRepositoryImpl(
      remote: CategoryRemoteDataSourceImpl(
        baseUrl: Uri.parse('https://api.example.invalid'),
        httpClient: client,
      ),
      connectionChecker: connection,
    );
    final result = await repository.listCategories();
    print(
      'PROBE $label right=${result.getRight().toNullable()} '
      'code=${result.getLeft().toNullable()?.code} '
      'cause=${result.getLeft().toNullable()?.cause}',
    );
  }

  testWidgets('probe category parsing', (tester) async {
    await probe('valid', [_row()]);
    await probe('empty-slug', [_row(slug: '')]);
    await probe('not-list', {'categories': []});
    await probe('ints', [1, 2, 3]);
  });
}
