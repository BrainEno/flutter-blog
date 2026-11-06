import 'dart:convert';

import 'package:belog/features/blog/data/datasources/category_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

CategoryRemoteDataSource _remote(MockClient client) =>
    CategoryRemoteDataSourceImpl(
      baseUrl: Uri.parse('https://api.example.invalid'),
      httpClient: client,
    );

void main() {
  test('debug valid payload', () async {
    Object? caught;
    String detail = 'none';
    try {
      final list = await _remote(
        MockClient((_) async => _data([_row()])),
      ).listCategories();
      detail = 'len=${list.length} name=${list.first.name}';
    } catch (error, stack) {
      caught = error;
      detail = '${error.runtimeType} :: $error :: $stack';
    }
    fail('caught=$caught detail=$detail');
  });

  test('debug empty slug', () async {
    Object? caught;
    String detail = 'none';
    try {
      await _remote(
        MockClient((_) async => _data([_row(slug: '')])),
      ).listCategories();
      detail = 'no throw';
    } catch (error, stack) {
      caught = error;
      detail = '${error.runtimeType} :: $error :: $stack';
    }
    fail('caught=$caught detail=$detail');
  });
}
