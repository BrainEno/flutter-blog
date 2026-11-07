import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/article_deep_link.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/pages/change_email_page.dart';
import 'package:belog/features/auth/presentation/pages/email_verification_page.dart';
import 'package:belog/features/auth/presentation/pages/change_password_page.dart';
import 'package:belog/features/auth/presentation/pages/login_page.dart';
import 'package:belog/features/auth/presentation/pages/signup_page.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/category_articles/bloc/category_articles_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/pages/categories_page.dart';
import 'package:belog/features/blog/presentation/pages/category_articles_page.dart';
import 'package:belog/features/blog/presentation/category_navigation.dart';
import 'package:belog/features/messages/presentation/pages/message_inbox_page.dart';
import 'package:belog/features/messages/presentation/pages/message_thread_page.dart';
import 'package:belog/features/user/presentation/pages/author_page.dart';
import 'package:belog/features/user/presentation/pages/author_relationships_page.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/pages/publish_queue_page.dart';
import 'package:belog/features/blog/presentation/pages/recycle_bin_page.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:belog/features/blog/presentation/blocs/tag_articles/bloc/tag_articles_bloc.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/pages/tag_articles_page.dart';
import 'package:belog/features/blog/presentation/tag_navigation.dart';
import 'package:belog/features/blog/presentation/pages/user_blogs_page.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/domain/usecases/author.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/domain/usecases/get_author_relationships.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:belog/features/user/presentation/bloc/author_search/author_search_cubit.dart';
import 'package:belog/features/user/presentation/pages/author_search_page.dart';
import 'package:belog/features/user/presentation/bloc/author/author_cubit.dart';
import 'package:belog/features/user/presentation/bloc/author_relationships/author_relationships_cubit.dart';
import 'package:belog/features/notifications/presentation/pages/notification_inbox_page.dart';
import 'package:belog/features/user/presentation/pages/about_page.dart';
import 'package:belog/features/user/presentation/pages/account_sessions_page.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/features/user/presentation/pages/profile_page.dart';
import 'package:belog/features/user/presentation/pages/reading_history_page.dart';

import 'package:belog/init_dependencies.dart';
import 'package:belog/router/home_shell.dart';
import 'package:belog/router/read_aloud_route_observers.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// One navigator per bottom-navigation tab so every tab keeps its own stack
/// while the shell itself stays alive across tab switches.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> feedNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'feed',
);
final GlobalKey<NavigatorState> searchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'search',
);
final GlobalKey<NavigatorState> savedNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'saved',
);
final GlobalKey<NavigatorState> profileNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'profile',
);

/// One [RouteObserver] per branch navigator: a single observer instance must
/// never be attached to more than one navigator at a time. They notify
/// [RouteAware] pages when the route above them pops, for example so the
/// saved list can refresh after returning from the viewer.
final RouteObserver<ModalRoute<void>> feedRouteObserver =
    RouteObserver<ModalRoute<void>>();
final RouteObserver<ModalRoute<void>> searchRouteObserver =
    RouteObserver<ModalRoute<void>>();
final RouteObserver<ModalRoute<void>> savedRouteObserver =
    RouteObserver<ModalRoute<void>>();
final RouteObserver<ModalRoute<void>> profileRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Route prefixes that require a signed-in user. Everything else (feed,
/// search, viewer, about and the auth pages) stays public.
const List<String> _protectedPrefixes = ['/saved', '/profile', '/editor'];

/// Builds the app [GoRouter].
///
/// Auth state comes from [appUserCubit]: every change re-runs [GoRouter]
/// redirects via [refreshListenable], which is what sends freshly signed-out
/// users away from protected routes and returns signed-in users to the
/// location they were trying to open.
GoRouter createAppRouter({
  required AppUserCubit appUserCubit,
  String initialLocation = '/',
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [rootReadAloudRouteObserver],
    initialLocation: initialLocation,
    refreshListenable: _StreamListenable(appUserCubit.stream),
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.pageNotFound),
              const SizedBox(height: 16),
              NoWaveButton(
                label: context.l10n.backToHome,
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    ),
    redirect: (context, state) {
      // An external link arrives as the route information itself: on a cold
      // start it is `PlatformDispatcher.defaultRouteName`, while a warm start
      // pushes it through the same provider (issue #21). Rewriting it here,
      // before matching, is what turns `nowave://article/<slug>` or the
      // canonical `https://<WEB_BASE_URL>/articles/<slug>` into the reader
      // this app already has - and leaves every other URL untouched.
      final deepLink = articleLocationFromDeepLink(state.uri);
      if (deepLink != null && deepLink != state.uri.toString()) {
        return deepLink;
      }
      final loggedIn = appUserCubit.state is AppUserLoggedIn;
      final inAuthFlow =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      final protected = _protectedPrefixes.any(
        (prefix) => state.matchedLocation.startsWith(prefix),
      );
      if (!loggedIn && protected) {
        return '/login?redirect=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (loggedIn && inAuthFlow) {
        return _sanitize(state.uri.queryParameters['redirect']) ?? '/';
      }
      return null;
    },
    routes: [
      // Public on purpose: the diagnostics report is exactly what a user
      // needs when signing in fails, and `/profile/about` sits behind the
      // auth guard (see [_protectedPrefixes]).
      GoRoute(
        path: '/about',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AboutPage(
          openDiagnostics: state.uri.queryParameters['diagnostics'] == '1',
        ),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => LoginPage(
          redirectTo: _sanitize(state.uri.queryParameters['redirect']),
        ),
      ),
      GoRoute(
        path: '/signup',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => SignUpPage(
          redirectTo: _sanitize(state.uri.queryParameters['redirect']),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: feedNavigatorKey,
            observers: [feedRouteObserver, feedReadAloudRouteObserver],
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogBloc>(),
                  child: const BlogPage(),
                ),
                routes: [
                  viewerRoute(),
                  editorRoute(),
                  authorRoute(),
                  tagRoute(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: searchNavigatorKey,
            observers: [searchRouteObserver, searchReadAloudRouteObserver],
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogSearchBloc>(),
                  child: const SearchBlogPage(),
                ),
                routes: [
                  viewerRoute(),
                  authorRoute(),
                  tagRoute(),
                  categoriesRoute(),
                  categoryRoute(),
                  GoRoute(
                    path: 'authors',
                    builder: (context, state) => BlocProvider(
                      create: (_) => AuthorSearchCubit(
                        searchAuthors: serviceLocator<SearchAuthors>(),
                      ),
                      child: const AuthorSearchPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: savedNavigatorKey,
            observers: [savedRouteObserver, savedReadAloudRouteObserver],
            routes: [
              GoRoute(
                path: '/saved',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogLikedBloc>(),
                  child: const SavedBlogsPage(),
                ),
                routes: [viewerRoute(), authorRoute(), tagRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: profileNavigatorKey,
            observers: [profileRouteObserver, profileReadAloudRouteObserver],
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
                routes: [
                  viewerRoute(),
                  editorRoute(),
                  authorRoute(),
                  tagRoute(),
                  GoRoute(
                    path: 'my-articles',
                    builder: (context, state) => MultiBlocProvider(
                      providers: [
                        BlocProvider(
                          create: (_) => serviceLocator<BlogByBloc>(),
                        ),
                        BlocProvider(
                          create: (_) => serviceLocator<BlogUploadBloc>(),
                        ),
                      ],
                      child: const UserBlogsPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'recycle-bin',
                        builder: (context, state) => BlocProvider(
                          create: (_) => serviceLocator<RecycleBinBloc>(),
                          child: const RecycleBinPage(),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => BlocProvider(
                      create: (_) => serviceLocator<UserEditBloc>(),
                      child: const EditUserInfoPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'change-password',
                    builder: (context, state) => ChangePasswordPage(
                      repository: serviceLocator<AccountSecurityRepository>(),
                      session: serviceLocator<NowaveSessionManager>(),
                    ),
                  ),
                  GoRoute(
                    path: 'change-email',
                    builder: (context, state) => ChangeEmailPage(
                      repository: serviceLocator<AccountSecurityRepository>(),
                      session: serviceLocator<NowaveSessionManager>(),
                    ),
                  ),
                  GoRoute(
                    path: 'email-verification',
                    builder: (context, state) => EmailVerificationPage(
                      repository: serviceLocator<AccountSecurityRepository>(),
                      session: serviceLocator<NowaveSessionManager>(),
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) => const NotificationInboxPage(),
                  ),
                  // Private conversations. `?to=<userId>` comes from an
                  // author page's "发私信": the inbox opens the conversation
                  // that already exists with that person, or offers to create
                  // one, instead of creating a duplicate.
                  GoRoute(
                    path: 'messages',
                    builder: (context, state) => MessageInboxPage(
                      startWith: state.uri.queryParameters['to'],
                    ),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => MessageThreadPage(
                          conversationId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const ReadingHistoryPage(),
                  ),
                  // What this device still owes the server (issue #23).
                  GoRoute(
                    path: 'publish-queue',
                    builder: (context, state) => const PublishQueuePage(),
                  ),
                  GoRoute(
                    path: 'sessions',
                    builder: (context, state) => const AccountSessionsPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The viewer route, nested inside every tab branch so it pushes onto that
/// tab's own navigator and keeps the bottom bar plus the tab's back stack.
/// `/view/:id` (the copy in the feed branch) is the in-app deep-link path,
/// and `core/utils/article_deep_link.dart` rewrites the external forms
/// (`nowave://article/<slug>`, `https://<WEB_BASE_URL>/articles/<slug>`) onto
/// it. `:id` is the article's public slug on the no-wave backend: a link only
/// addresses it, the server still decides whether it may be read, so a link
/// to a draft or a deleted article fails in the viewer like any other fetch.
GoRoute viewerRoute() {
  return GoRoute(
    path: 'view/:id',
    builder: (context, state) {
      final blogId = state.pathParameters['id']!;
      final extra = state.extra;
      return MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => serviceLocator<BlogLikedBloc>()),
          BlocProvider(
            create: (_) => BlogViewerCubit(
              getBlogById: serviceLocator<GetBlogById>(),
              blogId: blogId,
              initialBlog: extra is Blog ? extra : null,
            ),
          ),
          // The slug doubles as the comments key (issue #19); the bloc is
          // page-scoped and disposed with the viewer.
          BlocProvider(
            create: (_) => CommentBloc(
              getComments: serviceLocator<GetComments>(),
              createComment: serviceLocator<CreateComment>(),
              deleteComment: serviceLocator<DeleteComment>(),
              slug: blogId,
            ),
          ),
        ],
        child: BlogViewerPage(blogId: blogId),
      );
    },
  );
}

/// The public author profile page (issue #20), nested inside every tab
/// branch so it pushes onto the current tab's stack from the viewer's
/// author row or a comment's author. `:userId` is the stable user id
/// (Blog.posterId / Comment.authorId), not a slug.
GoRoute authorRoute() {
  return GoRoute(
    path: 'author/:userId',
    builder: (context, state) {
      final userId = state.pathParameters['userId']!;
      return MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthorCubit(
              getAuthorProfile: serviceLocator<GetAuthorProfile>(),
              followAuthor: serviceLocator<FollowAuthor>(),
              unfollowAuthor: serviceLocator<UnfollowAuthor>(),
              userId: userId,
            ),
          ),
          BlocProvider(create: (_) => serviceLocator<BlogByBloc>()),
        ],
        child: AuthorPage(userId: userId),
      );
    },
    routes: [
      for (final kind in AuthorRelationshipKind.values)
        GoRoute(
          path: kind.name,
          builder: (context, state) => BlocProvider(
            create: (_) => AuthorRelationshipsCubit(
              getRelationships: serviceLocator<GetAuthorRelationships>(),
              userId: state.pathParameters['userId']!,
              kind: kind,
            ),
            child: AuthorRelationshipsPage(kind: kind),
          ),
        ),
    ],
  );
}

/// The public category catalog, reached from the search tab.
///
/// Categories are the editors' filing system: the names are translated per
/// content language and the client keeps no copy, so the page reads the catalog
/// once per visit.
GoRoute categoriesRoute() {
  return GoRoute(
    path: 'categories',
    builder: (context, state) => BlocProvider(
      create: (_) => serviceLocator<CategoriesCubit>(),
      child: const CategoriesPage(),
    ),
  );
}

/// One category's articles. `:slug` is the server's opaque taxonomy slug, the
/// only address the route accepts; a tap may pass the resolved [CategoryRef]
/// through `extra` so the title does not have to wait for a lookup.
GoRoute categoryRoute() {
  return GoRoute(
    path: 'category/:slug',
    builder: (context, state) {
      final slug = categorySlugFromRoute(state.pathParameters['slug']!);
      return BlocProvider(
        create: (_) => serviceLocator<CategoryArticlesBloc>(),
        child: CategoryArticlesPage(
          slug: slug,
          knownName: categoryFromExtra(state.extra)?.name,
        ),
      );
    },
  );
}

/// The tag article list (issue #106), nested inside every tab branch so a tag
/// tapped in the feed, search results, an author's page or an article pushes
/// onto that tab's own stack and keeps the bottom bar plus its back stack.
/// `:name` is the stored tag value, not the server slug: the slug is opaque
/// and is resolved by the page itself.
GoRoute tagRoute() {
  return GoRoute(
    path: 'tag/:name',
    builder: (context, state) {
      final tag = tagFromRoute(state.pathParameters['name']!, state.extra);
      return BlocProvider(
        create: (_) => serviceLocator<TagArticlesBloc>(),
        child: TagArticlesPage(tag: tag),
      );
    },
  );
}

/// The editor route, nested under the feed branch (new article from the FAB)
/// and the profile branch (editing from "my articles"). The result of the
/// pushed route reports whether anything was published, updated or deleted so
/// the page below can refresh.
///
/// `extra` is either the [Blog] being edited or a [PublishQueueEntry] to resume
/// (the queue page), never both.
GoRoute editorRoute() {
  return GoRoute(
    path: 'editor',
    builder: (context, state) {
      final extra = state.extra;
      return BlocProvider(
        create: (_) => serviceLocator<BlogUploadBloc>(),
        child: BlogEditorPage(
          blog: extra is Blog ? extra : null,
          queueEntry: extra is PublishQueueEntry ? extra : null,
        ),
      );
    },
  );
}

/// Bridges a [Stream] (the auth cubit's state stream) into a [Listenable]
/// so [GoRouter] re-runs its redirect whenever the auth state changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((dynamic _) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Accepts only in-app absolute paths that are not part of the auth flow
/// itself, so a stale or crafted `redirect` parameter cannot loop the user
/// back into login or out of the app.
String? _sanitize(String? target) {
  if (target == null || !target.startsWith('/')) {
    return null;
  }
  if (target.startsWith('/login') || target.startsWith('/signup')) {
    return null;
  }
  return target;
}
