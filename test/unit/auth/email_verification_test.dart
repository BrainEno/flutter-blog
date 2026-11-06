import 'package:belog/features/auth/domain/email_verification.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_aBcD0';

void main() {
  test('the token is exactly 32 bytes of base64url', () {
    expect(_token.length, 43);
    expect(isVerificationToken(_token), isTrue);
    for (final bad in [
      '',
      'abc',
      'a' * 42,
      'a' * 44,
      '${'a' * 42}=',
      '${'a' * 42}!',
      '${'a' * 42} ',
      'AbCdEfGh-IjKlMnOpQrStUvWxYz0123456789_abCd0', // 43 characters
    ]) {
      expect(isVerificationToken(bad), isFalse, reason: bad);
    }
  });

  test('a whole mailed link yields its token', () {
    expect(
      extractVerificationToken(
        'https://wave.example.invalid/verify-email?token=$_token',
      ),
      _token,
    );
    // Ports, fragments and trailing whitespace survive a copy/paste.
    expect(
      extractVerificationToken(
        '  https://wave.example.invalid:8443/verify-email?token=$_token#done  ',
      ),
      _token,
    );
  });

  test('a link buried in a copied paragraph is still found', () {
    expect(
      extractVerificationToken(
        '请打开下面的链接确认这个邮箱属于你。链接只用一次，一天后失效。\n'
        'https://wave.example.invalid/verify-email?token=$_token\n',
      ),
      _token,
    );
  });

  test('a bare code, and a link whose query was dropped, both work', () {
    expect(extractVerificationToken(' $_token '), _token);
    expect(
      extractVerificationToken(
        'https://wave.example.invalid/verify-email/$_token',
      ),
      _token,
    );
  });

  test('text without a usable code returns nothing rather than a guess', () {
    for (final input in [
      '',
      '   ',
      'https://wave.example.invalid/verify-email',
      'https://wave.example.invalid/verify-email?token=short',
      'https://wave.example.invalid/verify-email?token=${'a' * 44}',
      'token=${'a' * 43}b',
      'confirm your address',
    ]) {
      expect(extractVerificationToken(input), isNull, reason: input);
    }
  });

  test('the status reads the address and the moment it was proven', () {
    final verified = AccountEmailStatus.fromMe({
      'id': 'user-a',
      'email': 'a@example.invalid',
      'emailVerifiedAt': '2025-01-02T03:04:05.000Z',
      'isEditor': false,
    });
    expect(verified.email, 'a@example.invalid');
    expect(verified.isVerified, isTrue);
    expect(verified.verifiedAt, DateTime.utc(2025, 1, 2, 3, 4, 5));

    final unverified = AccountEmailStatus.fromMe({
      'id': 'user-a',
      'email': 'a@example.invalid',
      'emailVerifiedAt': null,
    });
    expect(unverified.isVerified, isFalse);
  });

  test('an unreadable payload is unverified, never assumed proven', () {
    for (final data in [null, 'text', 42, <String, Object?>{}]) {
      final status = AccountEmailStatus.fromMe(data);
      expect(status.isVerified, isFalse, reason: '$data');
      expect(status.email, isEmpty);
    }
    // A malformed timestamp is not a verification either.
    expect(
      AccountEmailStatus.fromMe({
        'email': 'a@example.invalid',
        'emailVerifiedAt': 'yesterday',
      }).isVerified,
      isFalse,
    );
  });
}
