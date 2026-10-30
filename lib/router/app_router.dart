import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/features/auth/presentation/pages/login_page.dart';
import 'package:belog/features/auth/presentation/pages/signup_page.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/presentation/blocs/blog/blog_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_by/bloc/blog_by_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_liked/blog_liked_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_search/bloc/blog_search_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/blog_viewer/blog_viewer_cubit.dart';
import 'package:belog/features/blog/presentation/blocs/blog_upload/bloc/blog_upload_bloc.dart';
import 'package:belog/features/blog/presentation/pages/blog_editor_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_page.dart';
import 'package:belog/features/blog/presentation/pages/blog_viewer_page.dart';
import 'package:belog/features/blog/presentation/blocs/recycle_bin/recycle_bin_bloc.dart';
import 'package:belog/features/blog/presentation/pages/recycle_bin_page.dart';
import 'package:belog/features/blog/presentation/pages/saved_blogs_page.dart';
import 'package:belog/features/blog/presentation/pages/search_blog_page.dart';
import 'package:belog/features/blog/presentation/pages/user_blogs_page.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/presentation/pages/about_page.dart';
import 'package:belog/features/user/presentation/pages/edit_user_info_page.dart';
import 'package:belog/features/user/presentation/pages/profile_page.dart';
import 'package:belog/features/user/presentation/pages/reading_history_page.dart';

import 'package:belog/init_dependencies.dart';
import 'package:belog/router/home_shell.dart';
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
    initialLocation: initialLocation,
    refreshListenable: _StreamListenable(appUserCubit.stream),
    redirect: (context, state) {
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
            observers: [feedRouteObserver],
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogBloc>(),
                  child: const BlogPage(),
                ),
                routes: [viewerRoute(), editorRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: searchNavigatorKey,
            observers: [searchRouteObserver],
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogSearchBloc>(),
                  child: const SearchBlogPage(),
                ),
                routes: [viewerRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: savedNavigatorKey,
            observers: [savedRouteObserver],
            routes: [
              GoRoute(
                path: '/saved',
                builder: (context, state) => BlocProvider(
                  create: (_) => serviceLocator<BlogLikedBloc>(),
                  child: const SavedBlogsPage(),
                ),
                routes: [viewerRoute()],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: profileNavigatorKey,
            observers: [profileRouteObserver],
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
                routes: [
                  viewerRoute(),
                  editorRoute(),
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
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const ReadingHistoryPage(),
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
/// `/view/:id` (the copy in the feed branch) is the canonical deep-link
/// path; `:id` is the article's public slug on the no-wave backend.
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
        ],
        child: BlogViewerPage(blogId: blogId),
      );
    },
  );
}

/// The editor route, nested under the feed branch (new article from the FAB)
/// and the profile branch (editing from "my articles"). The result of the
/// pushed route reports whether anything was published, updated or deleted so
/// the page below can refresh.
GoRoute editorRoute() {
  return GoRoute(
    path: 'editor',
    builder: (context, state) {
      final extra = state.extra;
      return BlocProvider(
        create: (_) => serviceLocator<BlogUploadBloc>(),
        child: BlogEditorPage(blog: extra is Blog ? extra : null),
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
