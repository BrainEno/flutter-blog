import 'package:belog/core/utils/avatar_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absolute HTTP(S) avatars are used as they are', () {
    expect(
      resolveAvatarUrl('https://api.example.invalid/api/v1/media/a.webp'),
      'https://api.example.invalid/api/v1/media/a.webp',
    );
    expect(
      resolveAvatarUrl(' http://cdn.example.invalid/a.png '),
      'http://cdn.example.invalid/a.png',
    );
  });

  test('site-relative avatars need an explicit web origin', () {
    // The backend accepts `/avatars/me.webp`; it belongs to the web deployment
    // and must never be resolved against the API origin.
    expect(resolveAvatarUrl('/avatars/me.webp'), isNull);
    expect(resolveAvatarUrl('/avatars/me.webp', webBaseUrl: ''), isNull);
    expect(
      resolveAvatarUrl(
        '/avatars/me.webp',
        webBaseUrl: 'https://site.example.invalid',
      ),
      'https://site.example.invalid/avatars/me.webp',
    );
    // A configured path is ignored: the avatar stays on the site origin.
    expect(
      resolveAvatarUrl(
        '/avatars/me.webp?size=2',
        webBaseUrl: 'https://site.example.invalid/base/',
      ),
      'https://site.example.invalid/avatars/me.webp?size=2',
    );
  });

  test('untrusted avatar values stay neutral', () {
    for (final value in <String>[
      '',
      '   ',
      '//evil.example/avatar.webp',
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      'file:///etc/passwd',
      'https://user:pass@evil.example/a.webp',
      'https://evil.example/a b.webp',
      '/avatars/\nheader',
      '/\\evil.example/a.webp',
      'avatars/me.webp',
    ]) {
      expect(resolveAvatarUrl(value), isNull, reason: value);
      expect(
        resolveAvatarUrl(value, webBaseUrl: 'https://site.example.invalid'),
        isNull,
        reason: value,
      );
    }
  });

  test('a malformed web origin is treated as unconfigured', () {
    for (final base in <String>[
      '//site.example.invalid',
      'https://user:pass@site.example.invalid',
      'site.example.invalid',
      'javascript:alert(1)',
    ]) {
      expect(
        resolveAvatarUrl('/avatars/me.webp', webBaseUrl: base),
        isNull,
        reason: base,
      );
    }
  });

  test('a missing value never pretends to be an image', () {
    expect(resolveAvatarUrl(null), isNull);
    expect(resolveAvatarUrl(null, webBaseUrl: 'https://site.test'), isNull);
  });
}
