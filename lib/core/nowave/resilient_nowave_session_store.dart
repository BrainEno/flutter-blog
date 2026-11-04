import 'dart:convert';

import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/utils/app_logger.dart';

/// The two media a session can live in.
enum NowaveSessionMedium { secure, sqlite }

/// The always-available side-channel that records which copy is current.
///
/// It holds no credential - only the medium name and the list of copies that
/// still need to be removed - so it can live in ordinary app metadata even
/// when the token store itself is broken (#102).
abstract interface class SessionAuthorityStore {
  Future<String?> readMarker();
  Future<void> writeMarker(String value);
}

/// [SessionAuthorityStore] on the app's SQLite `metadata` table.
///
/// A dedicated key, next to - never replacing - the user's other metadata,
/// drafts, caches and reading history.
class SqliteSessionAuthorityStore implements SessionAuthorityStore {
  static const markerKey = 'nowave_session_authority_v1';

  final AppDatabase database;
  const SqliteSessionAuthorityStore(this.database);

  @override
  Future<String?> readMarker() => database.readMetadata(markerKey);

  @override
  Future<void> writeMarker(String value) =>
      database.writeMetadata(markerKey, value);
}

/// Which copy of the session is current, and which copies are waiting to be
/// removed.
class _Marker {
  const _Marker({required this.medium, this.pendingRemoval = const {}});

  /// `null` means "this device has no session"; that is a positive statement,
  /// not a missing value, and it is what stops a failed clear from
  /// resurrecting an account on the next launch.
  final NowaveSessionMedium? medium;

  /// Copies that could not be removed yet; retried on every read.
  final Set<NowaveSessionMedium> pendingRemoval;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'medium': medium?.name ?? 'none',
    'pendingRemoval': pendingRemoval.map((medium) => medium.name).toList(),
  };

  static _Marker? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final name = decoded['medium'];
      final medium = _byName(name);
      final pending = <NowaveSessionMedium>{};
      final rawPending = decoded['pendingRemoval'];
      if (rawPending is List) {
        for (final entry in rawPending) {
          final match = _byName(entry);
          if (match != null) pending.add(match);
        }
      }
      // Unknown or unparsable payloads read as "no marker": the store then
      // falls back to inspecting both media instead of guessing.
      if (name != 'none' && medium == null) return null;
      return _Marker(medium: medium, pendingRemoval: pending);
    } on FormatException {
      return null;
    }
  }

  static NowaveSessionMedium? _byName(Object? name) {
    for (final medium in NowaveSessionMedium.values) {
      if (medium.name == name) return medium;
    }
    return null;
  }
}

/// A session store that survives one of its two media being broken.
///
/// The platform secure storage is preferred; the app's private SQLite slot is
/// the fallback. What makes the pair trustworthy is not redundancy but a
/// **marker**: a small record in ordinary app metadata naming the copy that is
/// current. Consequences, all of which are tested:
///
/// * A fresh install whose secure storage cannot be written still signs in -
///   the write falls through to SQLite and the marker follows it.
/// * A restart reads the marked copy only. A stale copy in the other medium is
///   never picked up "because it exists".
/// * A sign-out writes "no session" into the marker *before* touching either
///   copy. Even if both keychain and SQLite deletions fail, the session cannot
///   come back: the copies remain as disowned residue, and the user is told
///   the sign-out may not survive a restart instead of being told it worked.
/// * A crash between the marker write and the copy write leaves the marker
///   pointing at a medium without a copy; the read then uses the other copy,
///   which is the state from just before the attempt - never a different
///   account.
class ResilientNowaveSessionStore
    implements NowaveSessionStore, NowaveSessionSignOutStore {
  ResilientNowaveSessionStore({
    required NowaveSessionStore secure,
    required NowaveSessionStore sqlite,
    required SessionAuthorityStore authority,
    bool secureWritesAllowed = true,
  }) : _secure = secure,
       _sqlite = sqlite,
       _authority = authority,
       _secureWritesAllowed = secureWritesAllowed;

  final NowaveSessionStore _secure;
  final NowaveSessionStore _sqlite;
  final SessionAuthorityStore _authority;

  /// Whether the secure medium passed the startup probe. It stays readable
  /// either way: an existing keychain copy is still the best copy there is.
  final bool _secureWritesAllowed;

  /// Opens the session store for this launch.
  ///
  /// [canary] must be a store in the same medium as [secure] but bound to a
  /// separate key, so the probe never touches the session slot. A failing
  /// probe is not fatal: the store stays usable and reports the degradation
  /// once, instead of failing every sign-in with an unexplained storage error.
  static Future<ResilientNowaveSessionStore> open({
    required NowaveSessionStore secure,
    required NowaveSessionStore sqlite,
    required SessionAuthorityStore authority,
    required NowaveSessionStore canary,
  }) async {
    final secureWritesAllowed = await _probe(canary);
    if (!secureWritesAllowed) {
      AppLogger.error(
        'platform secure storage is unavailable; session writes fall back to '
        'the private SQLite store',
      );
    }
    return ResilientNowaveSessionStore(
      secure: secure,
      sqlite: sqlite,
      authority: authority,
      secureWritesAllowed: secureWritesAllowed,
    );
  }

  /// Writes, reads back and removes a canary value.
  ///
  /// The canary is a session with empty fields: it exercises the real
  /// encoding path while carrying nothing that could be personal. It is
  /// always removed, and a failure to remove it is itself a probe failure.
  static Future<bool> _probe(NowaveSessionStore canary) async {
    final probe = NowaveSessionData(
      userId: '',
      email: '',
      accessToken: '',
      refreshToken: '',
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
      refreshExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    try {
      await canary.write(probe);
      final readBack = await canary.read();
      await canary.clear();
      return readBack != null;
    } catch (error, stackTrace) {
      AppLogger.debug('secure storage probe failed: ${error.runtimeType}');
      AppLogger.error(
        'probing platform secure storage failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Whether this store is running without a working secure medium.
  bool get isDegraded => !_secureWritesAllowed;

  NowaveSessionStore _forMedium(NowaveSessionMedium medium) =>
      medium == NowaveSessionMedium.secure ? _secure : _sqlite;

  NowaveSessionMedium _other(NowaveSessionMedium medium) =>
      medium == NowaveSessionMedium.secure
      ? NowaveSessionMedium.sqlite
      : NowaveSessionMedium.secure;

  @override
  Future<NowaveSessionData?> read() async {
    final marker = await _readMarker();
    if (marker == null) {
      // An install that predates the marker: trust the secure copy first, then
      // the SQLite one, and record the decision so later reads are exact.
      for (final medium in _readOrder()) {
        final session = await _readCopy(medium);
        if (session != null) {
          try {
            await _writeMarker(_Marker(medium: medium));
          } catch (error) {
            AppLogger.debug(
              'recording the legacy session medium failed: '
              '${error.runtimeType}',
            );
          }
          return session;
        }
      }
      return null;
    }
    if (marker.pendingRemoval.isNotEmpty) await _reclaim(marker);
    final medium = marker.medium;
    if (medium == null) return null;
    final session = await _readCopy(medium);
    if (session != null) return session;
    // The marked copy is gone: either it was cleared, or the process died
    // between the marker and the copy write. The other copy is the previous
    // state, never a different account.
    return _readCopy(_other(medium));
  }

  @override
  Future<void> write(NowaveSessionData session) async {
    final previous = (await _readMarker())?.medium;
    Object? firstError;
    for (final medium in _writeOrder()) {
      var markerMoved = false;
      try {
        // The marker goes first: a crash after it leaves the session absent
        // rather than leaving an old copy in charge.
        await _writeMarker(
          _Marker(medium: medium, pendingRemoval: {_other(medium)}),
        );
        markerMoved = true;
        await _forMedium(medium).write(session);
        await _reclaim(
          _Marker(medium: medium, pendingRemoval: {_other(medium)}),
        );
        return;
      } catch (error, stackTrace) {
        firstError ??= error;
        AppLogger.error(
          'writing the session to the ${medium.name} store failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (markerMoved && previous != null) {
          // Point the marker back at the copy that was in charge before this
          // attempt, so a half-written fallback is not mistaken for the
          // current session.
          await _restoreMarker(previous);
        }
      }
    }
    throw SessionStoreException(
      '会话无法写入本地存储',
      code: 'session.storeUnavailable',
      cause: firstError,
    );
  }

  /// Records that [medium] holds the current copy.
  ///
  /// Used by the one-time migration, which writes and verifies the copy
  /// itself and only then lets the store take it into service. The other copy
  /// is queued for removal on the next read, so a legacy row that could not be
  /// deleted is retried rather than ignored.
  Future<void> adoptVerified(NowaveSessionMedium medium) =>
      _writeMarker(_Marker(medium: medium, pendingRemoval: {_other(medium)}));

  @override
  Future<void> clear() async {
    await clearForSignOut();
  }

  @override
  Future<SessionClearResult> clearForSignOut() async {
    final leftover = <NowaveSessionMedium>{};
    try {
      // Disown first. From this moment on a restart reads "no session", even
      // if the copies below survive.
      await _writeMarker(_Marker(medium: null));
    } catch (error, stackTrace) {
      AppLogger.error(
        'recording the sign-out marker failed; a restart may restore the '
        'account',
        error: error,
        stackTrace: stackTrace,
      );
      await _clearCopies(leftover);
      return SessionClearResult.failed;
    }
    await _clearCopies(leftover);
    if (leftover.isEmpty) return SessionClearResult.cleared;
    // Keep the leftovers on record so the next read retries the removal.
    try {
      await _writeMarker(_Marker(medium: null, pendingRemoval: leftover));
    } catch (error, stackTrace) {
      AppLogger.error(
        'recording the copies left behind by the sign-out failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return SessionClearResult.disowned;
  }

  Future<void> _clearCopies(Set<NowaveSessionMedium> leftover) async {
    for (final medium in NowaveSessionMedium.values) {
      try {
        await _forMedium(medium).clear();
      } catch (error, stackTrace) {
        leftover.add(medium);
        AppLogger.error(
          'clearing the ${medium.name} session copy failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Retries a removal that a previous sign-out could not finish. Failures
  /// keep the copy on the pending list; the next read tries again.
  Future<void> _reclaim(_Marker marker) async {
    if (marker.pendingRemoval.isEmpty) return;
    final remaining = <NowaveSessionMedium>{};
    for (final medium in marker.pendingRemoval) {
      try {
        await _forMedium(medium).clear();
      } catch (error) {
        remaining.add(medium);
        AppLogger.debug(
          'retrying the removal of the ${medium.name} session copy failed: '
          '${error.runtimeType}',
        );
      }
    }
    if (remaining.length == marker.pendingRemoval.length) return;
    try {
      await _writeMarker(
        _Marker(medium: marker.medium, pendingRemoval: remaining),
      );
    } catch (error) {
      AppLogger.debug(
        'recording the reclaimed session copies failed: '
        '${error.runtimeType}',
      );
    }
  }

  Future<NowaveSessionData?> _readCopy(NowaveSessionMedium medium) async {
    try {
      return await _forMedium(medium).read();
    } catch (error, stackTrace) {
      AppLogger.debug('reading the ${medium.name} session copy failed');
      AppLogger.error(
        'reading the ${medium.name} session copy failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<_Marker?> _readMarker() async {
    try {
      return _Marker.fromJson(await _authority.readMarker());
    } catch (error, stackTrace) {
      AppLogger.error(
        'reading the session authority marker failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _writeMarker(_Marker marker) =>
      _authority.writeMarker(jsonEncode(marker.toJson()));

  Future<void> _restoreMarker(NowaveSessionMedium previous) async {
    try {
      await _writeMarker(_Marker(medium: previous));
    } catch (error) {
      AppLogger.error(
        'restoring the previous session authority failed',
        error: error,
      );
    }
  }

  /// The secure copy is authoritative; SQLite is only read when secure is
  /// unreadable *and* the marker points there.
  List<NowaveSessionMedium> _readOrder() => _secureWritesAllowed
      ? const [NowaveSessionMedium.secure, NowaveSessionMedium.sqlite]
      : const [NowaveSessionMedium.sqlite, NowaveSessionMedium.secure];

  List<NowaveSessionMedium> _writeOrder() => _secureWritesAllowed
      ? const [NowaveSessionMedium.secure, NowaveSessionMedium.sqlite]
      : const [NowaveSessionMedium.sqlite];
}
