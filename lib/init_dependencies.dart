import 'dart:io';

import 'package:belog/core/network/api_connection_checker.dart';
import 'package:belog/core/network/api_origin_report.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/resilient_nowave_session_store.dart';
import 'package:belog/core/nowave/secure_nowave_session_store.dart';
import 'package:belog/core/nowave/session_store_migration.dart';
import 'package:belog/core/nowave/sqlite_nowave_session_store.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/di/api_base_url_setting.dart';
import 'package:belog/di/app_modules.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The app's one container. Pages resolve from it; tests build their own.
final serviceLocator = GetIt.instance;

/// The composition root: everything that must exist *before* the feature
/// modules can be registered.
///
/// It validates the compiled-in API origin, opens the database, opens the
/// session store, builds the one HTTP client and session manager, and
/// restores the session. Every feature's registrations live in `lib/di/`
/// (one file per feature, listed in `appModules`) so a new feature does not
/// edit this file (#304).
///
/// Throws when the API origin is missing or invalid or local storage cannot
/// be opened; the boot sequence renders that failure.
Future<void> initDependencies() async {
  final uri = parseApiBaseUrlSetting(AppSecrets.apiBaseUrl);

  // Say which backend this build targets before anything else can fail. The
  // origin is compiled in, so "it cannot connect" is usually answered by this
  // one line: a CI QA build carries `https://example.invalid`, and a
  // release/profile build cannot use a plain-HTTP origin at all. The same line
  // reaches the diagnostics report header (about page) for installed builds.
  AppLogger.debug(describeApiOrigin(uri, debugBuild: kDebugMode));

  final directory = await getApplicationDocumentsDirectory();
  final database = AppDatabase.open(File('${directory.path}/belog.sqlite'));
  // Isar is no longer supported (#107). A leftover `default.isar` is left in
  // place untouched; tell the log once so a developer knows why local drafts
  // from a pre-SQLite build did not show up.
  if (await database.takeRetiredIsarNotice(directory)) {
    AppLogger.debug(
      'found default.isar but the Isar importer was removed; '
      'local drafts from that build are not imported',
    );
  }

  // The no-wave session. Tokens live in the platform secure storage
  // (issue #46); the SQLite-backed store remains as the migration source
  // and the fallback when the secure store is unavailable. A small marker in
  // the SQLite metadata table says which of the two copies is current, so a
  // failed clear cannot resurrect an account and a broken keychain cannot
  // silently lose one (#102).
  final sessionStore = await openSessionStore(
    legacy: SqliteNowaveSessionStore(database),
    secure: const SecureNowaveSessionStore(),
    canary: const SecureNowaveSessionStore(
      key: SecureNowaveSessionStore.canaryKey,
    ),
    authority: SqliteSessionAuthorityStore(database),
  );
  final connectivity = ApiConnectionChecker(uri);
  final httpClient = http.Client();
  final sessionManager = NowaveSessionManager(
    client: NowaveApiClient(
      baseUrl: uri,
      httpClient: httpClient,
      connectivityEvidence: connectivity,
    ),
    store: sessionStore,
  );
  final apiClient = NowaveApiClient(
    baseUrl: uri,
    authenticator: sessionManager,
    httpClient: httpClient,
    connectivityEvidence: connectivity,
  );
  // The only eager registration: it owns the shared HTTP client, so it is
  // made before the modules and closes the client when the container resets.
  serviceLocator.registerSingleton<ConnectionChecker>(
    connectivity,
    dispose: (_) {
      connectivity.close();
      httpClient.close();
    },
  );
  await sessionManager.restore();

  registerAppModules(
    serviceLocator,
    DependencyContext(
      database: database,
      apiBaseUrl: uri,
      apiClient: apiClient,
      sessionManager: sessionManager,
      documentsDirectory: directory,
    ),
  );
}
