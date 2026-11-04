import 'package:belog/core/nowave/transport/unauthorized_replay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exactly one reaction may follow a 401: a second rotation of the same family
/// revokes the session, and a token that changed under an unfenced client may
/// belong to another account.
void main() {
  UnauthorizedReplay decide({
    String? sent = 'token-a',
    String? current = 'token-a',
    bool bound = true,
    bool allowRefresh = true,
  }) {
    return decideUnauthorizedReplay(
      sentToken: sent,
      currentToken: current,
      sessionBound: bound,
      allowRefresh: allowRefresh,
    );
  }

  test('a call that must not replay reports nothing to do', () {
    expect(decide(allowRefresh: false), UnauthorizedReplay.notApplicable);
    expect(
      decide(sent: null, current: null, allowRefresh: false),
      UnauthorizedReplay.notApplicable,
    );
  });

  test('an unauthenticated 401 is not replayable', () {
    expect(
      decide(sent: null, current: 'token-a'),
      UnauthorizedReplay.notApplicable,
    );
  });

  test('a token rotated by another request is reused for the session', () {
    expect(
      decide(sent: 'token-a', current: 'token-b', bound: true),
      UnauthorizedReplay.reuseCurrentToken,
    );
  });

  test('an unfenced client fails closed when the token changed', () {
    expect(
      decide(sent: 'token-a', current: 'token-b', bound: false),
      UnauthorizedReplay.surfaceOriginal,
      reason: 'the new token may belong to another account',
    );
  });

  test('the same token means nobody refreshed yet', () {
    expect(
      decide(sent: 'token-a', current: 'token-a'),
      UnauthorizedReplay.refreshFirst,
    );
  });

  test('a 401 after the session ended is surfaced, never refreshed', () {
    expect(
      decide(sent: 'token-a', current: null, bound: true),
      UnauthorizedReplay.surfaceOriginal,
    );
    expect(
      decide(sent: 'token-a', current: null, bound: false),
      UnauthorizedReplay.surfaceOriginal,
    );
  });
}
