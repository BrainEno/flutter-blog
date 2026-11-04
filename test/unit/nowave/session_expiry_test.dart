import 'package:belog/core/nowave/session/session_data.dart';
import 'package:belog/core/nowave/session/session_expiry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole proactive-refresh policy is a mapping from the tokens the app
/// holds to one action; these cases are that table.
void main() {
  final now = DateTime.utc(2026, 1, 1, 12);
  const lead = Duration(seconds: 30);
  const fiveMinutes = Duration(minutes: 5);
  const sevenDays = Duration(days: 7);
  const tenSeconds = Duration(seconds: 10);
  const fiveSeconds = Duration(seconds: 5);
  const expired = Duration(seconds: -1);

  NowaveSessionData session({
    String accessToken = 'access',
    required Duration accessIn,
    required Duration refreshIn,
    bool spent = false,
  }) => NowaveSessionData(
    userId: 'u1',
    email: 'user@example.invalid',
    accessToken: accessToken,
    refreshToken: 'refresh',
    accessExpiresAt: now.add(accessIn),
    refreshExpiresAt: now.add(refreshIn),
    refreshTokenSpent: spent,
  );

  SessionExpiryAction decide(NowaveSessionData value) =>
      decideSessionExpiry(session: value, now: now, leadTime: lead);

  test('a comfortably valid access token is reused', () {
    final value = session(accessIn: fiveMinutes, refreshIn: sevenDays);

    expect(decide(value), SessionExpiryAction.reuseAccessToken);
  });

  test('an access token inside the lead time is rotated', () {
    final value = session(accessIn: tenSeconds, refreshIn: sevenDays);

    expect(decide(value), SessionExpiryAction.rotate);
  });

  test('an expired access token is rotated', () {
    final value = session(accessIn: expired, refreshIn: sevenDays);

    expect(decide(value), SessionExpiryAction.rotate);
  });

  test('an empty access token is rotated', () {
    final value = session(
      accessToken: '',
      accessIn: fiveMinutes,
      refreshIn: sevenDays,
    );

    expect(decide(value), SessionExpiryAction.rotate);
  });

  test('an expired refresh token ends an unrefreshed session', () {
    final value = session(accessIn: fiveSeconds, refreshIn: Duration.zero);

    expect(decide(value), SessionExpiryAction.endWithExpiredRefreshToken);
  });

  test('a still usable access token outlives an expired refresh token', () {
    final value = session(accessIn: fiveMinutes, refreshIn: Duration.zero);

    // The access token is the only remaining life of the session.
    expect(decide(value), SessionExpiryAction.reuseAccessToken);
  });

  test('a spent refresh token never triggers a rotation', () {
    final value = session(
      accessIn: fiveSeconds,
      refreshIn: sevenDays,
      spent: true,
    );

    expect(decide(value), SessionExpiryAction.keepAccessTokenOnly);
  });

  test('a spent refresh token plus a dead access token ends it', () {
    final value = session(accessIn: expired, refreshIn: sevenDays, spent: true);

    expect(decide(value), SessionExpiryAction.endWithSpentRefreshToken);
  });

  test('an exactly-now refresh expiry counts as expired', () {
    final value = session(accessIn: fiveSeconds, refreshIn: Duration.zero);

    expect(decide(value), SessionExpiryAction.endWithExpiredRefreshToken);
  });

  test('an access token expiring exactly at the lead time is rotated', () {
    final value = session(accessIn: lead, refreshIn: sevenDays);

    // A token that expires exactly at the lead time is not "after" it.
    expect(decide(value), SessionExpiryAction.rotate);
  });
}
