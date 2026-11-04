import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/tag_ref.dart';
import 'package:belog/features/blog/domain/tag_paging.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockResolveTag extends Mock implements ResolveTag {}

class _MockGetArticlesByTag extends Mock implements GetArticlesByTag {}

class _ResolveParamsFake extends Fake implements ResolveTagParams {}

class _ArticlesParamsFake extends Fake implements TagArticlesParams {}

const _tag = TagRef(name: '夜航', slug: 'yehang-1a2b');

Blog _blog(String id) => Blog(
  id: id,
  title: '文章 $id',
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const ['夜航'],
  updatedAt: DateTime.utc(2026),
);

List<Blog> _page(int start, int count) => [
  for (var i = 0; i < count; i++) _blog('a${start + i}'),
];

void main() {
  late _MockResolveTag resolveTag;
  late _MockGetArticlesByTag getArticlesByTag;
  late TagArticlesBloc bloc;

  setUpAll(() {
    registerFallbackValue(_ResolveParamsFake());
    registerFallbackValue(_ArticlesParamsFake());
  });

  setUp(() {
    resolveTag = _MockResolveTag();
    getArticlesByTag = _MockGetArticlesByTag();
    when(
      () => resolveTag(any()),
    ).thenAnswer((_) async => right(_tag));
    bloc = TagArticlesBloc(
      resolveTag: resolveTag,
      getArticlesByTag: getArticlesByTag,
    );
    addTearDown(bloc.close);
  });

  Future<TagArticlesState> settled() => bloc.stream.firstWhere(
    (state) =>
        state is TagArticlesSuccess ||
        state is TagArticlesFailure ||
        state is TagArticlesUnknown,
  );

  test('a full first page reports that more exist', () async {
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right(_page(0, kTagPageSize)));
    final done = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    final state = await done as TagArticlesSuccess;

    expect(state.articles, hasLength(kTagPageSize));
    expect(state.hasMore, isTrue);
    expect(state.tag, _tag);
    verify(() => getArticlesByTag(any())).called(1);
  });

  test('a short first page is the whole list', () async {
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer((_) async => right(_page(0, 3)));
    final done = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    final state = await done as TagArticlesSuccess;

    expect(state.articles, hasLength(3));
    expect(state.hasMore, isFalse);
  });

  test('load more appends without repeating a row', () async {
    var call = 0;
    when(() => getArticlesByTag(any())).thenAnswer((_) async {
      call += 1;
      if (call == 1) return right(_page(0, kTagPageSize));
      // The server repeats the last row it already handed out.
      return right([_blog('a19'), _blog('a20')]);
    });

    final first = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    await first;

    final second = bloc.stream.firstWhere(
      (state) => state is TagArticlesSuccess && !state.hasMore,
    );
    bloc.add(TagArticlesMoreRequested());
    final state = await second as TagArticlesSuccess;

    expect(state.articles, hasLength(kTagPageSize + 1));
    expect(
      state.articles.map((blog) => blog.id).toSet(),
      hasLength(kTagPageSize + 1),
    );
    expect(state.articles.last.id, 'a20');
    final params = verify(
      () => getArticlesByTag(captureAny()),
    ).captured.cast<TagArticlesParams>();
    expect(params.last.offset, kTagPageSize);
    expect(params.last.slug, _tag.slug);
  });

  test('an unknown tag is its own state and reads no articles', () async {
    when(() => resolveTag(any())).thenAnswer((_) async => right(null));

    final done = settled();
    bloc.add(TagArticlesRequested(tag: '不存在的标签'));
    final state = await done;

    expect(state, isA<TagArticlesUnknown>());
    expect((state as TagArticlesUnknown).tag, '不存在的标签');
    verifyNever(() => getArticlesByTag(any()));
  });

  test('a tag that vanished mid-session is reported as unknown', () async {
    when(
      () => getArticlesByTag(any()),
    ).thenAnswer(
      (_) async => left(
        const Failure(
          '这个标签已不存在',
          kind: FailureKind.server,
          code: 'tag.notFound',
        ),
      ),
    );

    final done = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    final state = await done;

    expect(state, isA<TagArticlesUnknown>());
  });

  test('a network failure is retryable and keeps no rows', () async {
    var attempts = 0;
    when(() => getArticlesByTag(any())).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) return left(Failure.networkOffline());
      return right(_page(0, 2));
    });

    final failed = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    expect(await failed, isA<TagArticlesFailure>());

    final retried = settled();
    bloc.add(TagArticlesRefreshed());
    final state = await retried as TagArticlesSuccess;

    expect(state.articles, hasLength(2));
    // The slug is resolved once; refresh does not pay for it again.
    verify(() => resolveTag(any())).called(1);
  });

  test('a failed next page keeps what is on screen', () async {
    var call = 0;
    when(() => getArticlesByTag(any())).thenAnswer((_) async {
      call += 1;
      if (call == 1) return right(_page(0, kTagPageSize));
      return left(Failure.networkOffline());
    });

    final first = settled();
    bloc.add(TagArticlesRequested(tag: '夜航'));
    await first;

    final failedMore = bloc.stream.firstWhere(
      (state) =>
          state is TagArticlesSuccess && state.loadMoreFailure != null,
    );
    bloc.add(TagArticlesMoreRequested());
    final state = await failedMore as TagArticlesSuccess;

    expect(state.articles, hasLength(kTagPageSize));
    expect(state.loadingMore, isFalse);
    expect(state.hasMore, isTrue, reason: '失败不等于没有下一页');
  });

  test('a blank tag never reaches the server', () async {
    final done = settled();
    bloc.add(TagArticlesRequested(tag: '  '));
    expect(await done, isA<TagArticlesUnknown>());
    verifyNever(() => resolveTag(any()));
    verifyNever(() => getArticlesByTag(any()));
  });
}
