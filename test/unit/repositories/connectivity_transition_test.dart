import 'dart:async';
import 'dart:io';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:belog/features/auth/data/datasources/profile_cache_store.dart';
import 'package:belog/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/comment_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/data/repositories/comment_repository_impl.dart';
import 'package:belog/features/blog/domain/entities/blog_feed_page.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _BlogRemote extends Mock implements BlogRemoteDataSource {}

class _BlogLocal extends Mock implements BlogLocalDataSource {}

class _Comments extends Mock implements CommentRemoteDataSource {}

class _AuthRemote extends Mock implements AuthRemoteDataSource {}

class _Profile extends Mock implements ProfileCacheStore {}

class _History extends Mock implements ReadingHistoryStore {}

final _base = Uri.parse('https://api.example.invalid');
final _article = BlogModel(
  id: 'slug',
  articleId: 'id',
  title: 'title',
  content: 'body',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026),
);
final _session = NowaveSessionData(
  userId: 'author',
  email: 'author@example.invalid',
  accessToken: 'token',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

void main() {
  late _BlogRemote blogRemote;
  late _BlogLocal local;
  late _Comments comments;
  late _AuthRemote authRemote;
  late _Profile profile;
  late _History history;
  late ApiConnectionChecker checker;
  late BlogRepositoryImpl blog;
  late AuthRepositoryImpl auth;
  var probes = 0;
  var offline = false;

  setUpAll(() => registerFallbackValue(<BlogModel>[]));
  setUp(() {
    probes = 0;
    offline = false;
    blogRemote = _BlogRemote();
    local = _BlogLocal();
    comments = _Comments();
    authRemote = _AuthRemote();
    profile = _Profile();
    history = _History();
    checker = ApiConnectionChecker(
      _base,
      clientFactory: () => MockClient((_) async {
        probes++;
        if (offline) throw const SocketException('disconnected');
        return http.Response('', 200);
      }),
    );
    blog = BlogRepositoryImpl(blogRemote, local, checker);
    auth = AuthRepositoryImpl(
      authRemote,
      checker,
      profile,
      readingHistoryStore: history,
    );
    when(() => authRemote.currentSession).thenReturn(_session);
    when(() => authRemote.sessionGeneration).thenReturn(1);
    when(
      () => profile.read(userId: any(named: 'userId')),
    ).thenAnswer((_) async => null);
  });
  tearDown(() => checker.close());

  test(
    'detail, related and comments share one concurrent health request',
    () async {
      final gate = Completer<http.Response>();
      var healthCount = 0;
      final shared = ApiConnectionChecker(
        _base,
        clientFactory: () => MockClient((_) {
          healthCount++;
          return gate.future;
        }),
      );
      addTearDown(shared.close);
      final sharedBlog = BlogRepositoryImpl(blogRemote, local, shared);
      final sharedComments = CommentRepositoryImpl(
        commentRemoteDataSource: comments,
        connectionChecker: shared,
      );
      when(
        () => blogRemote.getBlogById('slug'),
      ).thenAnswer((_) async => _article);
      when(
        () => local.uploadLocalBlogs(blogs: any(named: 'blogs')),
      ).thenAnswer((_) async {});
      when(
        () => blogRemote.getRelatedArticles('slug'),
      ).thenAnswer((_) async => [_article]);
      when(
        () => comments.getComments('slug'),
      ).thenAnswer((_) async => CommentPage(items: const [], nextCursor: null));
      final detail = sharedBlog.getBlogById('slug');
      final related = sharedBlog.getRelatedArticles('slug');
      final commentPage = sharedComments.getComments('slug');
      await Future<void>.delayed(Duration.zero);
      expect(healthCount, 1);
      gate.complete(http.Response('', 200));
      expect((await detail).isRight(), isTrue);
      expect((await related).isRight(), isTrue);
      expect((await commentPage).isRight(), isTrue);
      expect(healthCount, 1);
    },
  );

  test('offline from first probe keeps cached home page and detail', () async {
    offline = true;
    when(
      () => local.loadBlogs(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => [_article]);
    when(() => local.loadBlogById('slug')).thenAnswer((_) async => _article);
    final feed = await blog.getAllBlogs(page: 1);
    final detail = await blog.getBlogById('slug');
    feed.fold((f) => fail(f.message), (page) {
      expect(page.source, BlogFeedSource.cache);
      expect(page.blogs.single.id, 'slug');
    });
    expect(detail.getRight().toNullable()?.id, 'slug');
    verifyNever(() => blogRemote.getAllBlogs(page: any(named: 'page')));
    verifyNever(() => blogRemote.getBlogById(any()));
    expect(probes, 2); // failures are deliberately not retained
  });

  test(
    'transport failure immediately after successful probe falls back to cached home',
    () async {
      when(
        () => blogRemote.getAllBlogs(page: 1),
      ).thenThrow(const SocketException('gone'));
      when(
        () => local.loadBlogs(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [_article]);
      final result = await blog.getAllBlogs(page: 1);
      result.fold((f) => fail(f.message), (page) {
        expect(page.source, BlogFeedSource.cache);
        expect(page.blogs.single.id, 'slug');
      });
      expect(probes, 1);
    },
  );

  test('network-pinned feed never silently changes to cache', () async {
    when(
      () => blogRemote.getAllBlogs(page: 2),
    ).thenThrow(const SocketException('gone'));
    final result = await blog.getAllBlogs(
      page: 2,
      source: BlogFeedSource.network,
    );
    expect(result.getLeft().toNullable()?.kind, FailureKind.network);
    verifyNever(
      () => local.loadBlogs(
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });

  for (final failure in [
    const SocketException('gone'),
    const HttpException('gone'),
    http.ClientException('gone'),
    const ServerException('lost', kind: FailureKind.network),
  ]) {
    test(
      'detail transport ${failure.runtimeType} uses cached article',
      () async {
        when(() => blogRemote.getBlogById('slug')).thenThrow(failure);
        when(
          () => local.loadBlogById('slug'),
        ).thenAnswer((_) async => _article);
        final result = await blog.getBlogById('slug');
        expect(result.getRight().toNullable()?.id, 'slug');
        verify(() => local.loadBlogById('slug')).called(1);
        verifyNever(() => local.uploadLocalBlogs(blogs: any(named: 'blogs')));
      },
    );
  }

  test('detail without a cached article reports offline', () async {
    when(
      () => blogRemote.getBlogById('slug'),
    ).thenThrow(const SocketException('gone'));
    when(() => local.loadBlogById('slug')).thenAnswer((_) async => null);
    final result = await blog.getBlogById('slug');
    expect(result.getLeft().toNullable()?.kind, FailureKind.network);
  });

  test(
    'detail cache read failure after transport error stays storage failure',
    () async {
      when(
        () => blogRemote.getBlogById('slug'),
      ).thenThrow(const SocketException('gone'));
      when(
        () => local.loadBlogById('slug'),
      ).thenThrow(StateError('private storage details'));
      final result = await blog.getBlogById('slug');
      expect(result.getLeft().toNullable()?.kind, FailureKind.storage);
      expect(
        result.getLeft().toNullable()?.message,
        isNot(contains('private')),
      );
    },
  );

  for (final failure in [
    const ServerException('denied', kind: FailureKind.permission),
    const ServerException('missing', kind: FailureKind.validation),
    const ServerException('unavailable', kind: FailureKind.server),
    TimeoutException('slow'),
  ]) {
    test(
      'detail ${failure.runtimeType} does not conceal non-network errors',
      () async {
        when(() => blogRemote.getBlogById('slug')).thenThrow(failure);
        final result = await blog.getBlogById('slug');
        expect(result.isLeft(), isTrue);
        verifyNever(() => local.loadBlogById(any()));
      },
    );
  }

  test('offline startup restores only the selected account profile', () async {
    offline = true;
    when(() => profile.read(userId: 'author')).thenAnswer(
      (_) async => CachedProfile(
        displayName: 'cached',
        avatarUrl: '',
        website: '',
        updatedAt: DateTime.utc(2026),
      ),
    );
    final result = await auth.currentUser();
    result.fold((failure) => fail(failure.message), (user) {
      expect(user.id, 'author');
      expect(user.name, 'cached');
    });
    verify(() => profile.read(userId: 'author')).called(1);
    verifyNever(() => authRemote.getCurrentUserData());
  });

  for (final failure in [
    const SocketException('gone'),
    const HttpException('gone'),
    http.ClientException('gone'),
    const ServerException('lost', kind: FailureKind.network),
  ]) {
    test(
      'current user ${failure.runtimeType} restores confirmed offline identity',
      () async {
        when(() => authRemote.getCurrentUserData()).thenThrow(failure);
        when(() => profile.read(userId: 'author')).thenAnswer(
          (_) async => CachedProfile(
            displayName: 'saved',
            avatarUrl: '',
            website: '',
            updatedAt: DateTime.utc(2026),
          ),
        );
        final result = await auth.currentUser();
        result.fold((f) => fail(f.message), (user) {
          expect(user.id, 'author');
          expect(user.name, 'saved');
        });
        expect(probes, 1);
      },
    );
  }

  test(
    'transport failure without a persisted session never invents one',
    () async {
      when(() => authRemote.currentSession).thenReturn(null);
      when(
        () => authRemote.getCurrentUserData(),
      ).thenThrow(const SocketException('gone'));
      final result = await auth.currentUser();
      expect(result.getLeft().toNullable()?.kind, FailureKind.auth);
      verifyNever(() => profile.read(userId: any(named: 'userId')));
    },
  );

  for (final failure in [
    const NowaveApiException(
      statusCode: 403,
      code: 'FORBIDDEN',
      message: 'denied',
    ),
    const NowaveApiException(
      statusCode: 401,
      code: 'UNAUTHENTICATED',
      message: 'expired',
    ),
    TimeoutException('slow'),
    const ServerException('storage', kind: FailureKind.storage),
  ]) {
    test(
      'current user does not turn ${failure.runtimeType} into offline identity',
      () async {
        when(() => authRemote.getCurrentUserData()).thenThrow(failure);
        final result = await auth.currentUser();
        expect(result.isLeft(), isTrue);
        verifyNever(() => profile.read(userId: any(named: 'userId')));
      },
    );
  }

  test(
    'account switch during failing request cannot expose previous profile',
    () async {
      final gate = Completer<void>();
      var generation = 1;
      when(() => authRemote.sessionGeneration).thenAnswer((_) => generation);
      when(() => authRemote.getCurrentUserData()).thenAnswer((_) async {
        await gate.future;
        throw const SocketException('gone');
      });
      final pending = auth.currentUser();
      await Future<void>.delayed(Duration.zero);
      generation++;
      gate.complete();
      final result = await pending;
      expect(result.getLeft().toNullable()?.code, 'auth.sessionChanged');
      verifyNever(() => profile.read(userId: any(named: 'userId')));
    },
  );

  test(
    'account switch during profile read suppresses stale cached identity',
    () async {
      final gate = Completer<CachedProfile?>();
      var generation = 1;
      offline = true;
      when(() => authRemote.sessionGeneration).thenAnswer((_) => generation);
      when(() => profile.read(userId: 'author')).thenAnswer((_) => gate.future);
      final pending = auth.currentUser();
      await Future<void>.delayed(Duration.zero);
      generation++;
      gate.complete(
        CachedProfile(
          displayName: 'old',
          avatarUrl: '',
          website: '',
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(
        (await pending).getLeft().toNullable()?.code,
        'auth.sessionChanged',
      );
    },
  );

  test(
    'offline login still reports offline without sending credentials',
    () async {
      offline = true;
      final result = await auth.loginWithEmailPassword(
        email: 'a@example.invalid',
        password: 'not-a-secret',
      );
      expect(result.getLeft().toNullable()?.kind, FailureKind.network);
      verifyNever(
        () => authRemote.loginWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    },
  );
  test(
    'real SQLite cache stays locale-scoped after connectivity changes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final locale = ContentLocale();
      final cache = SqliteBlogCache(db, contentLocale: locale);
      await cache.uploadLocalBlogs(blogs: [_article]);
      final repository = BlogRepositoryImpl(blogRemote, cache, checker);
      when(
        () => blogRemote.getBlogById('slug'),
      ).thenThrow(const SocketException('gone'));
      final detail = await repository.getBlogById('slug');
      expect(detail.getRight().toNullable()?.content, 'body');
      locale.update(ContentLanguage.en);
      final english = await repository.getBlogById('slug');
      expect(english.getLeft().toNullable()?.kind, FailureKind.network);
      locale.update(ContentLanguage.zh);
      offline = true;
      checker.recordTransportFailure(_base.resolve('/api/v1/articles'));
      final home = await repository.getAllBlogs(page: 1);
      home.fold((failure) => fail(failure.message), (page) {
        expect(page.source, BlogFeedSource.cache);
        expect(page.blogs.single.id, 'slug');
      });
    },
  );

  test(
    'real SQLite profile fallback keeps backend and account scopes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = SqliteProfileCache(db, apiBaseUrl: _base);
      await cache.write(
        userId: 'author',
        profile: CachedProfile(
          displayName: 'confirmed',
          avatarUrl: '',
          website: '',
          updatedAt: DateTime.utc(2026),
        ),
      );
      final other = SqliteProfileCache(
        db,
        apiBaseUrl: Uri.parse('https://other.example.invalid'),
      );
      await other.write(
        userId: 'author',
        profile: CachedProfile(
          displayName: 'wrong backend',
          avatarUrl: '',
          website: '',
          updatedAt: DateTime.utc(2026),
        ),
      );
      when(
        () => authRemote.getCurrentUserData(),
      ).thenThrow(const SocketException('gone'));
      final repository = AuthRepositoryImpl(
        authRemote,
        checker,
        cache,
        readingHistoryStore: history,
      );
      final restored = await repository.currentUser();
      expect(restored.getRight().toNullable()?.name, 'confirmed');
      expect(await cache.read(userId: 'other'), isNull);
      expect(
        (await other.read(userId: 'author'))?.displayName,
        'wrong backend',
      );
    },
  );
}
