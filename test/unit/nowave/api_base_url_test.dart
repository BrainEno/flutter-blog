import 'package:belog/core/nowave/transport/api_base_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// URL composition is easy to break silently: a doubled prefix or a stray
/// query means every request fails in a way no test of the call site catches.
void main() {
  test('adds the versioned prefix to a bare origin', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://api.example.com'));

    expect(
      base.resolve('/articles').toString(),
      'https://api.example.com/api/v1/articles',
    );
  });

  test('keeps an explicit port, including the emulator alias', () {
    final base = ApiBaseUrl.parse(Uri.parse('http://10.0.2.2:4000'));

    expect(
      base.resolve('/health').toString(),
      'http://10.0.2.2:4000/api/v1/health',
    );
  });

  test('keeps a configured path prefix', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://example.com/backend'));

    expect(
      base.resolve('/articles').toString(),
      'https://example.com/backend/api/v1/articles',
    );
  });

  test('drops a trailing slash instead of doubling it', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://example.com/'));

    expect(
      base.resolve('/articles').toString(),
      'https://example.com/api/v1/articles',
    );
  });

  test('drops a configured query and fragment', () {
    final base = ApiBaseUrl.parse(
      Uri.parse('https://example.com?token=1#frag'),
    );

    expect(
      base.resolve('/articles').toString(),
      'https://example.com/api/v1/articles',
    );
    expect(
      base.resolve('/articles', {'page': '2'}).toString(),
      'https://example.com/api/v1/articles?page=2',
    );
  });

  test('an empty query map adds no question mark', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://example.com'));

    expect(
      base.resolve('/articles', {}).toString(),
      'https://example.com/api/v1/articles',
    );
  });

  test('rejects a base that already ends with the prefix', () {
    for (final url in [
      'https://example.com/api/v1',
      'https://example.com/api/v1/',
      'http://10.0.2.2:4000/api/v1',
    ]) {
      expect(
        () => ApiBaseUrl.parse(Uri.parse(url)),
        throwsArgumentError,
        reason: url,
      );
    }
  });

  test('never doubles a path that already carries the prefix', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://example.com'));

    expect(
      base.resolve('/api/v1/articles').toString(),
      'https://example.com/api/v1/articles',
    );
    expect(
      base.resolve('/api/v1/media/asset-1').toString(),
      'https://example.com/api/v1/media/asset-1',
    );
  });

  test('builds the immutable media route, not the server src field', () {
    final base = ApiBaseUrl.parse(Uri.parse('https://example.com'));

    expect(
      base.mediaUri('asset-1').toString(),
      'https://example.com/api/v1/media/asset-1',
    );
  });
}
