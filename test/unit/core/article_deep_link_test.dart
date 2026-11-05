import 'package:belog/core/utils/article_deep_link.dart';
import 'package:belog/core/utils/article_share.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract every platform integration feeds into the router (#21).
///
/// Only article links may be rewritten: everything else has to fall through to
/// the normal router (unknown-route page), or a crafted link could steer the
/// app somewhere the URL never asked for.
void main() {
  const web = 'https://bot-thk.example';

  group('custom scheme', () {
    test('nowave://article/<slug> opens the reader', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/poetry-1a2b')),
        '/view/poetry-1a2b',
      );
    });

    test('the empty-host form is understood too', () {
      // Some link producers write nowave:///article/<slug>.
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave:///article/poetry-1a2b')),
        '/view/poetry-1a2b',
      );
    });

    test('a trailing slash does not change the target', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/poetry-1a2b/')),
        '/view/poetry-1a2b',
      );
    });

    test('the case of the scheme is irrelevant', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('NOWAVE://article/poetry-1a2b')),
        '/view/poetry-1a2b',
      );
    });

    test('a percent-encoded slug is decoded then re-encoded once', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/%E8%AF%97-1a')),
        '/view/%E8%AF%97-1a',
      );
    });

    test('other hosts and targets are not articles', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://tag/%E8%AF%97')),
        isNull,
      );
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://authors/me')),
        isNull,
      );
      expect(articleLocationFromDeepLink(Uri.parse('nowave://')), isNull);
    });

    test('a missing or multi-segment slug is refused', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article')),
        isNull,
      );
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/')),
        isNull,
      );
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/a/b')),
        isNull,
        reason: '一个链接只指向一篇文章，多余的路径段不做猜测',
      );
    });

    test('a slug with whitespace or dots-only is refused', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/a%20b')),
        isNull,
      );
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/..')),
        isNull,
      );
      expect(
        articleLocationFromDeepLink(Uri.parse('nowave://article/${'a' * 201}')),
        isNull,
      );
    });
  });

  group('canonical web URL', () {
    test('a URL on the configured origin opens the reader', () {
      expect(
        articleLocationFromDeepLink(
          Uri.parse('$web/articles/poetry-1a2b'),
          webBaseUrl: web,
        ),
        '/view/poetry-1a2b',
      );
    });

    test('a configured base path is honoured', () {
      expect(
        articleLocationFromDeepLink(
          Uri.parse('https://bot-thk.example/zh/articles/poetry-1a2b'),
          webBaseUrl: 'https://bot-thk.example/zh',
        ),
        '/view/poetry-1a2b',
      );
      expect(
        articleLocationFromDeepLink(
          Uri.parse('https://bot-thk.example/articles/poetry-1a2b'),
          webBaseUrl: 'https://bot-thk.example/zh',
        ),
        isNull,
      );
    });

    test('a foreign host is never hijacked', () {
      expect(
        articleLocationFromDeepLink(
          Uri.parse('https://someone-else.example/articles/poetry-1a2b'),
          webBaseUrl: web,
        ),
        isNull,
      );
    });

    test('without a configured origin the https form is inert', () {
      expect(
        articleLocationFromDeepLink(Uri.parse('$web/articles/poetry-1a2b')),
        isNull,
        reason: 'WEB_BASE_URL 未配置时不猜测域名',
      );
    });

    test('the shared link parses back to the same article', () {
      // One implementation builds the link, another parses it: keep them in
      // step for every shape the share sheet can produce.
      for (final slug in ['poetry-1a2b', 'a', 'x-y-z-0123456789abcdef']) {
        final url = articleWebUrl(slug, webBaseUrl: '$web/');
        expect(url, isNotNull);
        expect(
          articleLocationFromDeepLink(Uri.parse(url!), webBaseUrl: '$web/'),
          '/view/$slug',
        );
      }
    });
  });

  group('in-app locations', () {
    test('normal app paths are not treated as deep links', () {
      for (final location in [
        '/',
        '/view/poetry-1a2b',
        '/search',
        '/profile/about',
        '/about?diagnostics=1',
      ]) {
        expect(
          articleLocationFromDeepLink(Uri.parse(location)),
          isNull,
          reason: '$location must keep its normal routing',
        );
      }
    });

    test('the shipped custom-scheme shape parses', () {
      // The builder that produced `nowave://article/<slug>` had no production
      // caller (the share sheet hands out the web URL), so it was removed in
      // the 2026-11 audit; this keeps the *shape* pinned to the manifest and
      // plist entries the app ships.
      expect(
        articleLocationFromDeepLink(
          Uri.parse('nowave://${kArticleDeepLinkHost}/poetry-1a2b'),
        ),
        '/view/poetry-1a2b',
      );
    });
  });

  group('cold start', () {
    test('the platform initial route becomes the reader', () {
      expect(
        initialLocationForRoute('nowave://article/poetry-1a2b'),
        '/view/poetry-1a2b',
      );
      expect(
        initialLocationForRoute('https://bot-thk.example/articles/poetry-1a2b'),
        '/',
        reason: 'WEB_BASE_URL 未配置时，未知来源的 https 链接按普通路由处理',
      );
    });

    test('normal launches still start at the feed', () {
      expect(initialLocationForRoute(null), '/');
      expect(initialLocationForRoute(''), '/');
      expect(initialLocationForRoute('/'), '/');
      expect(initialLocationForRoute('  '), '/');
    });

    test('an in-app initial path is kept, an unknown URL is not', () {
      expect(initialLocationForRoute('/view/abc'), '/view/abc');
      expect(initialLocationForRoute('garbage'), '/');
      expect(initialLocationForRoute('nowave://tag/x'), '/');
    });
  });
}
