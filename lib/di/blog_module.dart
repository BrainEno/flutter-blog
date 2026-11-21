import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/datasources/sqlite_blog_cache.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/data/views/nowave_article_view_recorder.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/delete_blog.dart';
import 'package:belog/features/blog/domain/usecase/get_all_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_articles_by_tag.dart';
import 'package:belog/features/blog/domain/usecase/get_author_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_blogs_by_poster.dart';
import 'package:belog/features/blog/domain/usecase/get_deleted_blogs.dart';
import 'package:belog/features/blog/domain/usecase/get_my_article_editions.dart';
import 'package:belog/features/blog/domain/usecase/get_my_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_related_articles.dart';
import 'package:belog/features/blog/domain/usecase/get_user_liked_blogs.dart';
import 'package:belog/features/blog/domain/usecase/is_blog_liked.dart';
import 'package:belog/features/blog/domain/usecase/offline_library.dart';
import 'package:belog/features/blog/domain/usecase/resolve_tag.dart';
import 'package:belog/features/blog/domain/usecase/restore_deleted_blog.dart';
import 'package:belog/features/blog/domain/usecase/search_blogs.dart';
import 'package:belog/features/blog/domain/usecase/toggle_like_blog.dart';
import 'package:belog/features/blog/domain/usecase/update_blog.dart';
import 'package:belog/features/blog/domain/usecase/upload_blog.dart';
import 'package:belog/features/blog/domain/views/article_view_recorder.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/offline_library/offline_library_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:get_it/get_it.dart';

/// Articles: the feed, reading, likes, search, tags, the offline library,
/// the recycle bin and the author's own articles.
void registerBlogModule(GetIt locator, DependencyContext context) {
  final apiClient = context.apiClient;
  final sessionManager = context.sessionManager;
  // One channel for the whole app: every page's BlogLikedBloc hears a save
  // made on any other page.
  locator.registerLazySingleton<SavedArticlesChanges>(
    SavedArticlesChanges.new,
    dispose: (changes) => changes.dispose(),
  );
  locator.registerLazySingleton<RecordArticleView>(
    () => RecordArticleView(
      NowaveArticleViewRecorder(client: apiClient, identity: sessionManager),
    ),
  );
  // Datasource
  locator
    ..registerFactory<BlogRemoteDataSource>(
      // `/me` routes are bound to the account that is active when they are
      // called, so an old page cannot read or write into a newer account.
      () => BlogRemoteDataSourceImpl(
        apiClient,
        identity: sessionManager,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    ..registerFactory<BlogLocalDataSource>(
      () => SqliteBlogCache(
        locator<AppDatabase>(),
        apiBaseUrl: context.apiBaseUrl,
        contentLocale: locator<ContentLocale>(),
      ),
    )
    // Repository
    ..registerFactory<BlogRepository>(
      () => BlogRepositoryImpl(
        locator<BlogRemoteDataSource>(),
        locator<BlogLocalDataSource>(),
        locator<ConnectionChecker>(),
      ),
    )
    // Usecases
    ..registerFactory(() => UploadBlog(locator<BlogRepository>()))
    ..registerFactory(() => GetAllBlogs(locator<BlogRepository>()))
    ..registerFactory(() => GetBlogById(locator<BlogRepository>()))
    ..registerFactory(() => SearchBlogs(locator<BlogRepository>()))
    ..registerFactory(() => GetOfflineLibrary(locator<BlogRepository>()))
    ..registerFactory(() => ClearOfflineLibrary(locator<BlogRepository>()))
    ..registerFactory(() => ToggleLikeBlog(locator<BlogRepository>()))
    ..registerFactory(() => IsBlogLiked(locator<BlogRepository>()))
    ..registerFactory(() => GetUserLikedBlogs(locator<BlogRepository>()))
    ..registerFactory(() => UpdateBlog(locator<BlogRepository>()))
    ..registerFactory(() => DeleteBlog(locator<BlogRepository>()))
    ..registerFactory(() => GetBlogsByPoster(locator<BlogRepository>()))
    ..registerFactory(() => GetAuthorArticles(locator<BlogRepository>()))
    ..registerFactory(() => GetMyArticles(locator<BlogRepository>()))
    ..registerFactory(() => GetMyArticleEditions(locator<BlogRepository>()))
    ..registerFactory(() => ResolveTag(locator<BlogRepository>()))
    ..registerFactory(() => GetArticlesByTag(locator<BlogRepository>()))
    ..registerFactory(() => GetDeletedBlogs(locator<BlogRepository>()))
    ..registerFactory(() => GetRelatedArticles(locator<BlogRepository>()))
    ..registerFactory(() => RestoreDeletedBlog(locator<BlogRepository>()))
    // Page-scoped blocs. Routes create one instance per page and dispose it
    // with the page, so request state never leaks across pages.
    ..registerFactory(() => BlogBloc(getAllBlogs: locator<GetAllBlogs>()))
    ..registerFactory(
      () => BlogUploadBloc(
        uploadBlog: locator<UploadBlog>(),
        updateBlog: locator<UpdateBlog>(),
        deleteBlog: locator<DeleteBlog>(),
      ),
    )
    ..registerFactory(() => BlogSearchBloc(searchBlogs: locator<SearchBlogs>()))
    ..registerFactory(
      () => OfflineLibraryCubit(
        getOfflineLibrary: locator<GetOfflineLibrary>(),
        clearOfflineLibrary: locator<ClearOfflineLibrary>(),
        contentLocale: locator<ContentLocale>(),
      ),
    )
    ..registerFactory(
      () => BlogLikedBloc(
        toggleBlogLike: locator<ToggleLikeBlog>(),
        isBlogLiked: locator<IsBlogLiked>(),
        getUserLikedBlogs: locator<GetUserLikedBlogs>(),
        sessionIdentity: sessionManager,
        savedChanges: locator<SavedArticlesChanges>(),
      ),
    )
    ..registerFactory(
      () => BlogByBloc(
        getAuthorArticles: locator<GetAuthorArticles>(),
        getMyArticles: locator<GetMyArticles>(),
        getMyArticleEditions: locator<GetMyArticleEditions>(),
      ),
    )
    ..registerFactory(
      () => TagArticlesBloc(
        resolveTag: locator<ResolveTag>(),
        getArticlesByTag: locator<GetArticlesByTag>(),
      ),
    )
    ..registerFactory(
      () => RecycleBinBloc(
        getDeletedBlogs: locator<GetDeletedBlogs>(),
        restoreDeletedBlog: locator<RestoreDeletedBlog>(),
        sessionIdentity: sessionManager,
      ),
    );
}
