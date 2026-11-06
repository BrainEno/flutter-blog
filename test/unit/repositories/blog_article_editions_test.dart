import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/article_editions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

BlogModel _blog(String locale) => BlogModel(
  id: 'slug',
  articleId: 'server-id',
  title: 'Title',
  content: 'Content',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2025),
  locale: locale,
);

void main() {
  late _Remote remote;
  late _Local local;
  late _Connection connection;
  late BlogRepositoryImpl repository;

  setUpAll(() => registerFallbackValue(_blog('zh-CN')));

  setUp(() {
    remote = _Remote();
    local = _Local();
    connection = _Connection();
    repository = BlogRepositoryImpl(remote, local, connection);
  });

  test('the editions read goes straight to the account source', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getMyArticleEditions(userId: 'user')).thenAnswer(
      (_) async => ArticleEditions(
        blogs: [_blog('zh-CN'), _blog('en')],
        locales: const ['zh-CN', 'zh-TW', 'en'],
      ),
    );

    final result = await repository.getMyArticleEditions(userId: 'user');
    final editions = result.getRight().toNullable();

    expect(editions, isNotNull);
    expect(editions!.isConfirmed, isTrue);
    expect(editions.blogs.map((blog) => blog.locale), ['zh-CN', 'en']);
    verifyNever(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')));
  });

  test('an unconfirmed answer stays unconfirmed', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(() => remote.getMyArticleEditions(userId: 'user')).thenAnswer(
      (_) async => ArticleEditions(blogs: [_blog('zh-CN')], locales: null),
    );

    final editions = (await repository.getMyArticleEditions(
      userId: 'user',
    )).getRight().toNullable();

    expect(editions!.isConfirmed, isFalse);
    expect(editions.locales, isNull);
  });

  test('offline is a network failure, never a cached stand-in', () async {
    when(() => connection.isConnected).thenAnswer((_) async => false);

    final failure = (await repository.getMyArticleEditions(
      userId: 'user',
    )).getLeft().toNullable();

    expect(failure!.kind, FailureKind.network);
    verifyNever(
      () => remote.getMyArticleEditions(userId: any(named: 'userId')),
    );
  });

  test('a signed-out read is refused before any request', () async {
    final failure = (await repository.getMyArticleEditions(
      userId: '',
    )).getLeft().toNullable();

    expect(failure!.kind, FailureKind.auth);
    verifyNever(
      () => remote.getMyArticleEditions(userId: any(named: 'userId')),
    );
  });

  test('an edit is fetched and written in its own edition', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    final original = BlogModel.fromNowaveArticle({
      'id': 'server-id',
      'slug': 'slug',
      'title': 'Title',
      'summary': 'summary',
      'authorId': 'author',
      'locale': 'en',
      'contentBlocksVersion': 0,
      'contentBlocks': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'b1', 'type': 'paragraph', 'text': 'Body'},
      ],
      'tags': <Map<String, dynamic>>[],
      'updatedAt': '2025-01-01T00:00:00.000Z',
    });
    when(
      () => remote.getBlogById('slug', locale: 'en'),
    ).thenAnswer((_) async => original);
    // An empty cover URL means "keep the current cover", so no upload runs.
    when(
      () => remote.editBlog(any()),
    ).thenAnswer((_) async => original.copyWith(title: 'New'));

    final result = await repository.editBlog(
      blogId: 'slug',
      title: 'New',
      content: 'Body',
      tags: const [],
      locale: 'en',
    );

    expect(result.isRight(), isTrue);
    verify(() => remote.getBlogById('slug', locale: 'en')).called(1);
    final written = verify(() => remote.editBlog(captureAny())).captured.single;
    expect((written as BlogModel).locale, 'en');
  });

  test('a restore names the edition of the tombstone', () async {
    when(() => connection.isConnected).thenAnswer((_) async => true);
    when(
      () => remote.restoreArticle('server-id', locale: 'zh-TW'),
    ).thenAnswer((_) async => _blog('zh-TW'));

    final result = await repository.restoreDeletedBlog(
      'server-id',
      locale: 'zh-TW',
    );

    expect(result.isRight(), isTrue);
    verify(() => remote.restoreArticle('server-id', locale: 'zh-TW')).called(1);
  });
}
