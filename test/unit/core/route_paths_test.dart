import 'dart:io';

import 'package:belog/router/route_paths.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [location] fits the go_router [pattern] (`/view/:id` style): same
/// number of segments, literal segments equal, parameters non-empty.
bool _fits(String pattern, String location) {
  final path = Uri.parse(location).path;
  final want = pattern.split('/');
  final got = path.split('/');
  if (want.length != got.length) return false;
  for (var i = 0; i < want.length; i++) {
    if (want[i].startsWith(':')) {
      if (got[i].isEmpty) return false;
    } else if (want[i] != got[i]) {
      return false;
    }
  }
  return true;
}

void main() {
  group('RoutePaths builders (#295)', () {
    test('encode every dynamic segment exactly once', () {
      expect(RoutePaths.view('poetry-1a2b'), '/view/poetry-1a2b');
      expect(RoutePaths.view('a/b?c'), '/view/a%2Fb%3Fc');
      expect(RoutePaths.view('诗'), '/view/%E8%AF%97');
      expect(RoutePaths.author('u 1'), '/author/u%201');
      expect(RoutePaths.tag('C#'), '/tag/C%23');
      expect(RoutePaths.category('a&b'), '/category/a%26b');
      expect(
        RoutePaths.authorRelationships('u1', 'followers'),
        '/author/u1/followers',
      );
      expect(RoutePaths.messageThread('c/1'), '/profile/messages/c%2F1');
      expect(RoutePaths.messagesWith('u&1'), '/profile/messages?to=u%261');
    });

    test('tab-scoped readers keep the tab prefix', () {
      expect(RoutePaths.searchView('a'), '/search/view/a');
      expect(RoutePaths.savedView('a'), '/saved/view/a');
      expect(RoutePaths.profileView('a'), '/profile/view/a');
      expect(RoutePaths.profileAuthor('u'), '/profile/author/u');
      expect(
        RoutePaths.offlineLibraryView('a'),
        '/search/offline-library/view/a',
      );
    });

    test('the builders agree with shellBranchLocation', () {
      expect(
        shellBranchLocation(Uri.parse('/saved'), RoutePaths.view('a')),
        RoutePaths.savedView('a'),
      );
      expect(
        shellBranchLocation(
          Uri.parse('/profile/history'),
          RoutePaths.view('a'),
        ),
        RoutePaths.profileView('a'),
      );
      expect(
        shellBranchLocation(Uri.parse('/search?q=x'), RoutePaths.categories),
        RoutePaths.searchCategories,
      );
    });

    test('withRedirect encodes the target and leaves null alone', () {
      expect(RoutePaths.withRedirect(RoutePaths.login, null), '/login');
      expect(
        RoutePaths.withRedirect(RoutePaths.login, '/'),
        '/login?redirect=%2F',
      );
      expect(
        RoutePaths.withRedirect(RoutePaths.signup, '/view/a?x=1'),
        '/signup?redirect=%2Fview%2Fa%3Fx%3D1',
      );
      final parsed = Uri.parse(
        RoutePaths.withRedirect(RoutePaths.login, '/saved/view/a b'),
      );
      expect(
        parsed.queryParameters[RoutePaths.redirectQuery],
        '/saved/view/a b',
      );
    });

    test('the diagnostics shortcut opens the public About page', () {
      final uri = Uri.parse(RoutePaths.aboutDiagnostics);
      expect(uri.path, RoutePaths.about);
      expect(uri.queryParameters[RoutePaths.diagnosticsQuery], '1');
    });
  });

  group('RoutePaths agree with the RouteSegments patterns', () {
    test('every builder fits the pattern its route declares', () {
      final cases = <String, String>{
        '/${RouteSegments.view}': RoutePaths.view('a'),
        '/${RouteSegments.author}': RoutePaths.author('u'),
        '/${RouteSegments.tag}': RoutePaths.tag('t'),
        '/${RouteSegments.category}': RoutePaths.category('s'),
        '${RoutePaths.search}/${RouteSegments.view}': RoutePaths.searchView(
          'a',
        ),
        '${RoutePaths.saved}/${RouteSegments.view}': RoutePaths.savedView('a'),
        '${RoutePaths.profile}/${RouteSegments.view}': RoutePaths.profileView(
          'a',
        ),
        '${RoutePaths.profile}/${RouteSegments.author}':
            RoutePaths.profileAuthor('u'),
        '${RoutePaths.profile}/${RouteSegments.messages}/'
            '${RouteSegments.messageThread}': RoutePaths.messageThread(
          'c',
        ),
        '${RoutePaths.search}/${RouteSegments.offlineLibrary}/'
            '${RouteSegments.view}': RoutePaths.offlineLibraryView(
          'a',
        ),
      };
      for (final entry in cases.entries) {
        expect(
          _fits(entry.key, entry.value),
          isTrue,
          reason: '${entry.value} does not fit ${entry.key}',
        );
      }
    });

    test('the parameter names are the ones the patterns declare', () {
      expect(RouteSegments.view, endsWith(':${RouteSegments.idParam}'));
      expect(RouteSegments.author, endsWith(':${RouteSegments.userIdParam}'));
      expect(RouteSegments.category, endsWith(':${RouteSegments.slugParam}'));
      expect(RouteSegments.tag, endsWith(':${RouteSegments.nameParam}'));
      expect(RouteSegments.messageThread, ':${RouteSegments.idParam}');
    });
  });

  group('access rules', () {
    test('protected prefixes cover saved, profile and the editor', () {
      expect(RoutePaths.isProtected(RoutePaths.saved), isTrue);
      expect(RoutePaths.isProtected(RoutePaths.history), isTrue);
      expect(RoutePaths.isProtected(RoutePaths.editor), isTrue);
      expect(RoutePaths.isProtected(RoutePaths.profileEditor), isTrue);
      expect(RoutePaths.isProtected(RoutePaths.feed), isFalse);
      expect(RoutePaths.isProtected(RoutePaths.view('a')), isFalse);
      expect(RoutePaths.isProtected(RoutePaths.searchView('a')), isFalse);
      expect(RoutePaths.isProtected(RoutePaths.about), isFalse);
      expect(RoutePaths.isProtected(RoutePaths.login), isFalse);
    });

    test('the auth flow lists exactly the four sign-in pages', () {
      expect(RoutePaths.authFlow, [
        RoutePaths.login,
        RoutePaths.signup,
        RoutePaths.forgotPassword,
        RoutePaths.resetPassword,
      ]);
    });
  });

  test('the router tree reads every segment from RouteSegments', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    // No pattern is written as a literal any more.
    expect(RegExp(r"path:\s*'").hasMatch(router), isFalse);
    const segments = [
      'view',
      'author',
      'categories',
      'category',
      'tag',
      'editor',
      'offlineLibrary',
      'authors',
      'myArticles',
      'recycleBin',
      'editProfile',
      'changePassword',
      'changeEmail',
      'emailVerification',
      'about',
      'notifications',
      'messages',
      'messageThread',
      'history',
      'publishQueue',
      'sessions',
    ];
    final missing = [
      for (final name in segments)
        if (!router.contains('RouteSegments.$name,')) name,
    ];
    expect(missing, isEmpty, reason: 'unused segments: $missing');
  });
}
