import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/resilient_nowave_session_store.dart';
import 'package:belog/core/utils/app_logger.dart';

/// Opens the session store for this launch, migrating a legacy SQLite copy
/// into the platform secure storage on the way.
///
/// The result is always a [ResilientNowaveSessionStore]: which medium actually
/// holds the bytes is its business, not the app's, and that is what makes a
/// broken keychain survivable instead of an unexplained sign-out (#102).
///
/// Migration rules, all idempotent because every launch re-runs them:
///
/// * A legacy row is copied into the secure store and **read back** before the
///   legacy row is removed. A copy that cannot be verified is never deleted,
///   so an unreadable keychain cannot lose the session.
/// * A failure at any step keeps the SQLite copy in charge for this launch and
///   the next launch retries. Losing the ability to migrate is a degraded
///   state, not a sign-out.
/// * A crash between the secure write and the legacy clear re-runs the
///   migration; the legacy copy is only ever read when it is the marked one.
Future<ResilientNowaveSessionStore> openSessionStore({
  required NowaveSessionStore legacy,
  required NowaveSessionStore secure,
  required NowaveSessionStore canary,
  required SessionAuthorityStore authority,
}) async {
  final store = await ResilientNowaveSessionStore.open(
    secure: secure,
    sqlite: legacy,
    authority: authority,
    canary: canary,
  );
  await _migrateLegacyCopy(legacy: legacy, secure: secure, store: store);
  return store;
}

Future<void> _migrateLegacyCopy({
  required NowaveSessionStore legacy,
  required NowaveSessionStore secure,
  required ResilientNowaveSessionStore store,
}) async {
  NowaveSessionData? migration;
  try {
    migration = await legacy.read();
  } catch (e, stackTrace) {
    AppLogger.error(
      'reading the legacy session copy failed; keeping the SQLite copy for '
      'this launch',
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }
  if (migration == null) return;
  try {
    await secure.write(migration);
  } catch (e, stackTrace) {
    // Nothing was written: the SQLite copy stays in charge and the next
    // launch retries.
    AppLogger.error(
      'migrating the session to secure storage failed; keeping the SQLite '
      'copy for this launch',
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }
  // Verify before deleting: a keychain write that silently dropped the value
  // must not cost the user their session.
  NowaveSessionData? readBack;
  try {
    readBack = await secure.read();
  } catch (e, stackTrace) {
    AppLogger.error(
      'verifying the migrated session failed; keeping the SQLite copy',
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }
  if (readBack?.refreshToken != migration.refreshToken ||
      readBack?.accessToken != migration.accessToken) {
    // The secure copy cannot be trusted: keep the SQLite copy in charge and
    // let the store remove the bad copy on the next read.
    AppLogger.error(
      'the migrated session did not read back; keeping the SQLite copy',
    );
    await store.adoptVerified(NowaveSessionMedium.sqlite);
    return;
  }
  try {
    await legacy.clear();
  } catch (e, stackTrace) {
    // Both copies exist and the marker will name the secure one, so the stale
    // row is residue rather than a second session; the store retries its
    // removal on the next read.
    AppLogger.error(
      'removing the migrated SQLite session copy failed; it will be retried '
      'on the next launch',
      error: e,
      stackTrace: stackTrace,
    );
  }
  await store.adoptVerified(NowaveSessionMedium.secure);
  AppLogger.debug('session store migrated to platform secure storage');
}
