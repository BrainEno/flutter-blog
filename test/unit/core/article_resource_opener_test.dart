import 'package:belog/core/utils/article_resource_opener.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the one door between a server-supplied address and the platform.
///
/// The whitelist itself is pinned by `article_resource_url_test.dart`, in
/// `test/unit/blog/`; what
/// this file owns is the combination, because that is where the author page
/// once diverged (issue #369): a value can be well formed and still not be
/// something this app may open, and the launcher must never see the difference.
///
/// Every case injects a launcher. The real one needs a platform channel, and a
/// test that reached for it would either fail or - worse for a security rule -
/// quietly do nothing while looking like it checked something.
void main() {
  /// Shapes that must never leave the app, whatever the platform would accept.
  const unsafe = [
    'javascript:alert(1)',
    'file:///etc/passwd',
    'data:text/html,<h1>hi</h1>',
    'intent://example#Intent;scheme=http;end',
    '//evil.example/download',
    'http://user:pass@evil.example',
    'https://example.invalid/a\nb',
    ' https://example.invalid/padded',
  ];

  /// An opener that records what would have been launched, and answers
  /// [opens] - the platform refusing a valid address is its own case.
  ArticleResourceOpener recording(List<Uri> seen, {bool opens = true}) {
    return ArticleResourceOpener(
      launch: (uri) async {
        seen.add(uri);
        return opens;
      },
    );
  }

  /// The same, with a web origin, which a test can only supply by injection:
  /// `WEB_BASE_URL` is compiled in.
  ArticleResourceOpener against(List<Uri> seen, String base) {
    return ArticleResourceOpener(
      webBaseUrl: base,
      launch: (uri) async {
        seen.add(uri);
        return true;
      },
    );
  }

  test('an unsafe address is rejected before the launcher runs', () async {
    for (final value in unsafe) {
      final seen = <Uri>[];
      final outcome = await recording(seen).open(value);
      expect(outcome, ArticleResourceOutcome.rejected, reason: value);
      expect(seen, isEmpty, reason: '$value reached the launcher');
    }
  });

  test('an accepted address is handed over once, resolved', () async {
    final seen = <Uri>[];
    final opener = recording(seen);
    final outcome = await opener.open('https://example.invalid/site');
    expect(outcome, ArticleResourceOutcome.opened);
    expect(seen, [Uri.parse('https://example.invalid/site')]);
  });

  test('a refusal is reported, not retried', () async {
    final seen = <Uri>[];
    final opener = recording(seen, opens: false);
    final outcome = await opener.open('https://example.invalid/site');
    expect(outcome, ArticleResourceOutcome.unavailable);
    expect(seen.length, 1, reason: 'the door must not retry on its own');
  });

  test('a relative address needs a base before it is a link', () async {
    // Without a base the web app's origin is unknown, and guessing one from
    // the API would open a site the reader never chose.
    final withoutBase = <Uri>[];
    final rejected = await recording(withoutBase).open('/articles/slug');
    expect(rejected, ArticleResourceOutcome.rejected);
    expect(withoutBase, isEmpty);

    // With a base the value becomes a real link, and what the launcher gets is
    // the absolute address - the half of the rule the page test cannot cover.
    final withBase = <Uri>[];
    final opener = against(withBase, 'https://web.example.invalid');
    expect(opener.accepts('/articles/slug'), isTrue);
    final outcome = await opener.open('/articles/slug');
    expect(outcome, ArticleResourceOutcome.opened);
    expect(withBase, [Uri.parse('https://web.example.invalid/articles/slug')]);
  });

  test('a base that is not a clean origin keeps relatives inert', () async {
    for (final base in ['', '   ', 'not a url', '//web.example.invalid']) {
      final seen = <Uri>[];
      final opener = against(seen, base);
      final outcome = await opener.open('/articles/slug');
      expect(outcome, ArticleResourceOutcome.rejected, reason: 'base: "$base"');
      expect(seen, isEmpty, reason: 'base: "$base"');
    }
  });

  test('accepts agrees with open for every shape', () async {
    // A widget decides between a tappable button and inert copy with `accepts`.
    // If the two ever disagreed, a reader could tap something the door then
    // refuses - or lose a link that would have opened.
    for (final value in [...unsafe, 'https://example.invalid/site', 'x']) {
      final seen = <Uri>[];
      final opener = recording(seen);
      final outcome = await opener.open(value);
      final openedSomething = outcome != ArticleResourceOutcome.rejected;
      expect(opener.accepts(value), openedSomething, reason: value);
    }
  });

  test('a launcher failure propagates to the caller that handles it', () async {
    // The markdown renderer keeps its own logging around the door, so an
    // exception must not be swallowed into a quiet `unavailable`.
    final opener = ArticleResourceOpener(
      launch: (uri) async => throw StateError('platform channel failed'),
    );
    await expectLater(
      opener.open('https://example.invalid/site'),
      throwsA(isA<StateError>()),
    );
  });
}
