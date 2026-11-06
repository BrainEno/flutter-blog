import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_category.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetCategory extends Mock implements GetCategory {}

class _MockGetArticlesByCategory extends Mock
    implements GetArticlesByCategory {}

class _ArticlesParamsFake extends Fake implements CategoryArticlesParams {}

const _category = CategoryRef(
  slug: 'essay-1a2b',
  name: '随笔',
  description: '短小的日常记录',
);

Blog _blog(String id) => Blog(
  id: id,
  title: '文章 $id',
  content: '正文',
  posterId: 'u1',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);

List<Blog> _page(int start, int count) => [
  for (var i = 0; i < count; i++) _blog('a${start + i}'),
];

void main() {
  late _MockGetCategory getCategory;
  late _MockGetArticlesByCategory getArticlesByCategory;
  late CategoryArticlesBloc bloc;

  setUpAll(() => registerFallbackValue(_ArticlesParamsFake()));

  setUp(() {
    getCategory = _MockGetCategory();
    getArticlesByCategory = _MockGetArticlesByCategory();
    when(
      () => getCategory(_category.slug),
    ).thenAnswer((_) async => right(_category));
    bloc = CategoryArticlesBloc(
      getCategory: getCategory,
      getArticlesByCategory: getArticlesByCategory,
    );
    addTearDown(bloc.close);
  });

  Future<CategoryArticlesState> settled() => bloc.stream.firstWhere(
    (state) =>
        state is CategoryArticlesSuccess ||
        state is CategoryArticlesFailure ||
        state is CategoryArticlesNotFound,
  );

  test('a full first page reports that more exist', () async {
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right(_page(0, kCategoryPageSize)));

    final done = settled();
    bloc.add(CategoryArticlesRequested(slug: _category.slug));
    final state = await done as CategoryArticlesSuccess;

    expect(state.articles, hasLength(kCategoryPageSize));
    expect(state.hasMore, isTrue);
    expect(state.category, _category);
    verify(() => getCategory(_category.slug)).called(1);
  });

  test('a short first page is the whole list', () async {
    when(
      () => getArticlesByCategory(any()),
    ).thenAnswer((_) async => right(_page(0, 3)));

    final done = settled();
    bloc.add(CategoryArticlesRequested(slug: _category.slug));
    final state = await done as CategoryArticlesSuccess;

    expect(state.articles, hasLength(3));
    expect(state.hasMore, isFalse);
  });

  test('load more appends without repeating a row', () async {
    var call = 0;
    when(() => getArticlesByCategory(any())).thenAnswer((_) async {
      call += 1;
      if (call == 1) return right(_page(0, kCategoryPageSize));
      // The server repeats the last row it already handed out.
      return right([_blog('a19'), _blog('a20')]);
    });

    final first = settled();
    bloc.add(CategoryArticlesRequested(slug: _category.slug));
    await first;

    final second = bloc.stream.firstWhere(
      (state) => state is CategoryArticlesSuccess && !state.hasMore,
    );
    bloc.add(CategoryArticlesMoreRequested());
    final state = await second as CategoryArticlesSuccess;

    expect(state.articles, hasLength(kCategoryPageSize + 1));
    expect(
      state.articles.map((blog) => blog.id).toSet(),
      hasLength(kCategoryPageSize + 1),
    );
    final params = verify(
      () => getArticlesByCategory(captureAny()),
    ).captured.cast<CategoryArticlesParams>();
    expect(params.last.offset, kCategoryPageSize);
    expect(params.last.slug, _category.slug);
  });

  test(
    'resolution happens once per visit, not once per page of articles',
    () async {
      when(
        () => getArticlesByCategory(any()),
      ).thenAnswer((_) async => right(_page(0, kCategoryPageSize)));

      final first = settled();
      bloc.add(CategoryArticlesRequested(slug: _category.slug));
      await first;

      final refreshed = bloc.stream.firstWhere(
        (state) => state is CategoryArticlesSuccess && !state.loadingMore,
      );
      bloc.add(CategoryArticlesRefreshed());
      await refreshed;

      verify(() => getCategory(_category.slug)).called(1);
    },
  );

  test('an unknown slug is its own state and reads no articles', () async {
    when(() => getCategory('gone-9z9z')).thenAnswer((_) async => right(null));

    final done = settled();
    bloc.add(CategoryArticlesRequested(slug: 'gone-9z9z'));
    final state = await done;

    expect(state, isA<CategoryArticlesNotFound>());
    expect((state as CategoryArticlesNotFound).slug, 'gone-9z9z');
    verifyNever(() => getArticlesByCategory(any()));
  });

  test('a category that vanished mid-session is reported as missing', () async {
    when(() => getArticlesByCategory(any())).thenAnswer(
      (_) async => left(
        const Failure(
          '这个分类已不存在',
          kind: FailureKind.server,
          code: 'category.notFound',
        ),
      ),
    );

    final done = settled();
    bloc.add(CategoryArticlesRequested(slug: _category.slug));
    final state = await done;

    expect(state, isA<CategoryArticlesNotFound>());
  });

  test(
    'a failed lookup is a retryable failure, not a missing category',
    () async {
      when(
        () => getCategory(_category.slug),
      ).thenAnswer((_) async => left(Failure.networkOffline()));

      final done = settled();
      bloc.add(CategoryArticlesRequested(slug: _category.slug));
      final state = await done;

      expect(state, isA<CategoryArticlesFailure>());
      verifyNever(() => getArticlesByCategory(any()));
    },
  );

  test('an empty slug never reaches the network', () async {
    final done = settled();
    bloc.add(CategoryArticlesRequested(slug: '  '));
    final state = await done;

    expect(state, isA<CategoryArticlesNotFound>());
    verifyNever(() => getCategory(any()));
    verifyNever(() => getArticlesByCategory(any()));
  });
}
