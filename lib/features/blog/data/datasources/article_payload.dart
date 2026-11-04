import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';

/// Requires an object payload from an endpoint that answers with one.
Map<String, dynamic> articlePayloadMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  throw ServerException(
    '服务器返回了无法解析的数据',
    kind: FailureKind.server,
    code: 'server.parse',
    cause: data,
  );
}

/// Maps a list payload to articles. Anything else is a server error rather
/// than an empty feed: an empty list must only ever mean "no articles".
List<BlogModel> articlePayloadList(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map<String, dynamic>>()
        .map(BlogModel.fromNowaveArticle)
        .toList();
  }
  throw ServerException(
    '服务器返回了无法解析的数据',
    kind: FailureKind.server,
    code: 'server.parse',
    cause: data,
  );
}
