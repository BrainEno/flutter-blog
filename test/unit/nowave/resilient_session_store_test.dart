import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/resilient_nowave_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session medium whose failures can be switched on per test.
class _FakeStore implements NowaveSessionStore {
  _FakeStore({this.failWrite = false});

  NowaveSessionData? stored;
  bool failRead = false;
  bool failWrite;
  bool failClear = false;
  int writes = 0;
  int clears = 0;

  @override
  Future<NowaveSessionData?> read() async {
    if (failRead) throw StateError('read unavailable');
    return stored;
  }

  @override
  Future<void> write(NowaveSessionData session) async {
    if (failWrite) throw StateError('write unavailable');
    writes++;
    stored = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (failClear) throw StateError('clear unavailable');
    stored = null;
  }
}

/// The always-writable side-channel; can also be made to fail.
class _FakeAuthority implements SessionAuthorityStore {
  _FakeAuthority();

  String? marker;
  bool failRead = false;
  bool failWrite = false;

  Map<String, dynamic>? get decoded =>
      marker == null ? null : jsonDecode(marker!) as Map<String, dynamic>;

  @override
  Future<String?> readMarker() async {
    if (failRead) throw StateError('marker unreadable');
    return marker;
  }

  @override
  Future<void> writeMarker(String value) async {
    if (failWrite) throw StateError('marker unwritable');
    marker = value;
  }
}

NowaveSessionData _session({String refreshToken = 'refresh-1'}) =>
    NowaveSessionData(
      userId: 'u1',
      email: 'user@example.invalid',
      accessToken: 'access-1',
      refreshToken: refreshToken,
      accessExpiresAt: DateTime.utc(2030),
      refreshExpiresAt: DateTime.utc(2030),
    );

({
  ResilientNowaveSessionStore store,
  _FakeStore secure,
  _FakeStore sqlite,
  _FakeAuthority authority,
})
_build({bool secureWritesAllowed = true}) {
  final secure = _FakeStore();
  final sqlite = _FakeStore();
  final authority = _FakeAuthority();
  return (
    store: ResilientNowaveSessionStore(
      secure: secure,
      sqlite: sqlite,
      authority: authority,
      secureWritesAllowed: secureWritesAllowed,
    ),
    secure: secure,
    sqlite: sqlite,
    authority: authority,
  );
}

/// A restart: a fresh store object over the same media and marker.
ResilientNowaveSessionStore _restart(
  ({
    ResilientNowaveSessionStore store,
    _FakeStore secure,
    _FakeStore sqlite,
    _FakeAuthority authority,
  })
  media, {
  bool secureWritesAllowed = true,
}) => ResilientNowaveSessionStore(
  secure: media.secure,
  sqlite: media.sqlite,
  authority: media.authority,
  secureWritesAllowed: secureWritesAllowed,
);

void main() {
  group('medium selection', () {
    test('a working secure medium wins and the old copy is removed', () async {
      final media = _build();
      media.sqlite.stored = _session(refreshToken: 'legacy');

      await media.store.write(_session());

      expect(media.secure.stored?.refreshToken, 'refresh-1');
      expect(media.sqlite.stored, isNull, reason: 'stale copy reclaimed');
      expect(media.authority.decoded?['medium'], 'secure');
      expect(
        (await _restart(media).read())?.refreshToken,
        'refresh-1',
        reason: 'a restart reads the marked copy',
      );
    });

    test('a broken secure medium falls back to SQLite, even on a fresh install '
        'and after a restart', () async {
      final media = _build(secureWritesAllowed: false);
      media.secure.failWrite = true;

      await media.store.write(_session());

      expect(media.secure.stored, isNull);
      expect(media.sqlite.stored?.refreshToken, 'refresh-1');
      expect(media.authority.decoded?['medium'], 'sqlite');

      final restarted = _restart(media, secureWritesAllowed: false);
      expect((await restarted.read())?.refreshToken, 'refresh-1');
    });

    test('a secure write that fails at runtime moves the marker too', () async {
      final media = _build();
      media.secure.failWrite = true;

      await media.store.write(_session());

      expect(media.sqlite.stored?.refreshToken, 'refresh-1');
      expect(media.authority.decoded?['medium'], 'sqlite');
    });

    test('without a marker, secure is read before SQLite', () async {
      final media = _build();
      media.sqlite.stored = _session(refreshToken: 'legacy');

      expect((await media.store.read())?.refreshToken, 'legacy');
      expect(media.authority.decoded?['medium'], 'sqlite');

      final secureFirst = _build();
      secureFirst.secure.stored = _session(refreshToken: 'secure');
      secureFirst.sqlite.stored = _session(refreshToken: 'legacy');

      expect((await secureFirst.store.read())?.refreshToken, 'secure');
    });

    test('an unreadable marked copy falls back to the other', () async {
      final media = _build();
      await media.store.write(_session());
      // The marked copy disappears (crash between marker and copy write, or a
      // wiped keychain); the other copy is the previous state, never another
      // account.
      media.secure.stored = null;
      media.secure.failRead = true;
      media.sqlite.stored = _session(refreshToken: 'previous');

      expect((await media.store.read())?.refreshToken, 'previous');
    });

    test('no medium at all is null, not an exception', () async {
      final media = _build();
      media.secure.failRead = true;
      media.sqlite.failRead = true;

      expect(await media.store.read(), isNull);
    });
  });

  group('write failures', () {
    test('a write that reaches no medium is reported, not swallowed', () async {
      final media = _build(secureWritesAllowed: false);
      media.sqlite.failWrite = true;

      await expectLater(
        media.store.write(_session()),
        throwsA(isA<SessionStoreException>()),
      );
      // The marker may already name the medium whose copy write failed. That
      // is the crash case the reader handles: nothing there, nothing restored.
      expect(await media.store.read(), isNull);
    });

    test('a failed fallback write restores the previous authority', () async {
      final media = _build();
      await media.store.write(_session(refreshToken: 'current'));
      media.secure.failWrite = true;
      media.sqlite.failWrite = true;

      await expectLater(
        media.store.write(_session(refreshToken: 'next')),
        throwsA(isA<SessionStoreException>()),
      );

      expect(media.authority.decoded?['medium'], 'secure');
      expect((await media.store.read())?.refreshToken, 'current');
    });
  });

  group('sign-out', () {
    test('a successful clear removes both copies', () async {
      final media = _build();
      await media.store.write(_session());

      expect(await media.store.clearForSignOut(), SessionClearResult.cleared);
      expect(media.secure.stored, isNull);
      expect(media.sqlite.stored, isNull);
      expect(media.authority.decoded?['medium'], 'none');
      expect(await _restart(media).read(), isNull);
    });

    test('a clear that fails everywhere still disowns the copies', () async {
      final media = _build();
      await media.store.write(_session());
      // Residue from an older build can sit in the fallback medium too.
      media.sqlite.stored = _session();
      media.secure.failClear = true;
      media.sqlite.failClear = true;

      expect(await media.store.clearForSignOut(), SessionClearResult.disowned);

      // Both copies are still there - and neither can bring the account back.
      expect(media.secure.stored, isNotNull);
      expect(media.sqlite.stored, isNotNull);
      expect(await _restart(media).read(), isNull);
      expect(
        media.authority.decoded?['pendingRemoval'],
        containsAll(<String>['secure', 'sqlite']),
      );
    });

    test('leftovers are retried on the next read', () async {
      final media = _build();
      await media.store.write(_session());
      media.secure.failClear = true;

      expect(await media.store.clearForSignOut(), SessionClearResult.disowned);
      expect(media.secure.stored, isNotNull);

      // The medium recovers; the next launch finishes the job.
      media.secure.failClear = false;
      final restarted = _restart(media);
      expect(await restarted.read(), isNull);
      expect(media.secure.stored, isNull);
    });

    test('an unwritable marker fails the sign-out', () async {
      final media = _build();
      await media.store.write(_session());
      media.authority.failWrite = true;

      expect(await media.store.clearForSignOut(), SessionClearResult.failed);

      // The copies are still cleared as far as the media allow it...
      expect(media.secure.stored, isNull);
      expect(media.sqlite.stored, isNull);
    });

    test('the marker carries no credential', () async {
      final media = _build();
      await media.store.write(_session());
      media.authority.marker = null;
      await media.store.clearForSignOut();

      final raw =
          (media.authority.marker ?? '') +
          (jsonEncode(media.authority.decoded ?? const {}));
      expect(raw, isNot(contains('access-1')));
      expect(raw, isNot(contains('refresh-1')));
      expect(raw, isNot(contains('@')));
    });
  });

  group('startup probe', () {
    test('a usable canary keeps the secure medium in charge', () async {
      final media = _build();
      final canary = _FakeStore();

      final store = await ResilientNowaveSessionStore.open(
        secure: media.secure,
        sqlite: media.sqlite,
        authority: media.authority,
        canary: canary,
      );

      expect(store.isDegraded, isFalse);
      expect(canary.stored, isNull, reason: 'the canary is removed again');
    });

    test('an unusable canary degrades to SQLite instead of failing', () async {
      final media = _build();
      final canary = _FakeStore(failWrite: true);

      final store = await ResilientNowaveSessionStore.open(
        secure: media.secure,
        sqlite: media.sqlite,
        authority: media.authority,
        canary: canary,
      );

      expect(store.isDegraded, isTrue);
      await store.write(_session());
      expect(media.sqlite.stored?.refreshToken, 'refresh-1');
      expect(media.authority.decoded?['medium'], 'sqlite');
    });
  });
}
