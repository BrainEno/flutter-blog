import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/utils/app_logger.dart';

/// Moves a persisted session from the legacy SQLite-backed store into
/// [secure], then returns the store the app should use from now on.
///
/// Failure policy: a storage hiccup must never sign the user out, so any
/// error keeps the legacy store for this launch (the next launch retries
/// - the migration is idempotent: writing the session again and clearing
/// the legacy slot again is always safe).
///
/// A crash between the secure write and the legacy clear also simply
/// re-runs the migration next launch with the same result.
Future<NowaveSessionStore> migrateSessionStoreToSecureStorage({
  required NowaveSessionStore legacy,
  required NowaveSessionStore secure,
}) async {
  try {
    final session = await legacy.read();
    if (session == null) {
      // Nothing to migrate: fresh install or already migrated.
      return secure;
    }
    await secure.write(session);
    await legacy.clear();
    AppLogger.debug('session store migrated to platform secure storage');
    return secure;
  } catch (e, stackTrace) {
    AppLogger.error(
      'migrating the session store to secure storage failed; '
      'keeping the SQLite-backed store for this launch',
      error: e,
      stackTrace: stackTrace,
    );
    return legacy;
  }
}
