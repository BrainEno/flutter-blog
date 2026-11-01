import 'package:belog/core/utils/article_resource_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts safe absolute and site-relative document resources', () {
    for (final url in [
      'https://media.example/a.png',
      'http://example.test:8080/x?y=1#z',
      '/images/a.png',
      '/articles/post?q=1',
    ]) {
      expect(isValidArticleResourceUrl(url), isTrue, reason: url);
    }
  });

  test('rejects dangerous or ambiguous resources', () {
    for (final url in [
      '',
      '//evil.example/path',
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      'file:///etc/passwd',
      'https://user:pass@example.test/image',
      'https://example.test/a b',
      ' https://example.test/a',
      '/\\evil.example/a',
      '/image\nheader',
      'images/relative.png',
      'https:///missing-host',
    ]) {
      expect(isValidArticleResourceUrl(url), isFalse, reason: url);
      expect(
        resolveArticleResourceUrl(url, webBaseUrl: 'https://site.test'),
        isNull,
      );
    }
  });

  test('resolves site paths only against an explicit trusted web base', () {
    const path = '/media/one.png?size=2';
    expect(resolveArticleResourceUrl(path, webBaseUrl: ''), isNull);
    expect(
      resolveArticleResourceUrl(path, webBaseUrl: 'https://u:p@site.test'),
      isNull,
    );
    expect(resolveArticleResourceUrl(path, webBaseUrl: '//site.test'), isNull);
    expect(
      resolveArticleResourceUrl(
        path,
        webBaseUrl: 'https://site.test/base',
      )?.toString(),
      'https://site.test/media/one.png?size=2',
    );
    expect(
      resolveArticleResourceUrl(
        'https://other.test/image',
        webBaseUrl: 'https://site.test',
      )?.toString(),
      'https://other.test/image',
    );
  });
}
