import 'package:belog/core/utils/article_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('articleWebUrl', () {
    test('builds the canonical web URL from the configured origin', () {
      expect(
        articleWebUrl('my-slug', webBaseUrl: 'https://bot-thk.example'),
        'https://bot-thk.example/articles/my-slug',
      );
    });

    test('trailing slashes on the origin are normalized', () {
      expect(
        articleWebUrl('my-slug', webBaseUrl: 'https://bot-thk.example/'),
        'https://bot-thk.example/articles/my-slug',
      );
    });

    test('no origin configured means no share URL (never a guessed link)',
        () {
      expect(articleWebUrl('my-slug', webBaseUrl: null), isNull);
      expect(articleWebUrl('my-slug', webBaseUrl: '  '), isNull);
    });

    test('an empty slug has no public page', () {
      expect(
        articleWebUrl('', webBaseUrl: 'https://bot-thk.example'),
        isNull,
      );
    });

    test('without the dart-define the default is null in tests', () {
      // WEB_BASE_URL is not set in the test runner; the share entry must
      // hide rather than share something unopenable.
      expect(articleWebUrl('my-slug'), isNull);
    });
  });
}
