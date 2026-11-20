import 'dart:io';

import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:get_it/get_it.dart';

/// What every feature module needs from the composition root.
///
/// `initDependencies` builds these once - the opened database, the validated
/// API origin and the one authenticated client with its session - and hands
/// the same instances to each module. A module never opens storage or builds
/// its own authenticated client: two session managers would refresh the same
/// rotating refresh token independently, which revokes the whole session
/// family (see docs/session-lifecycle.md).
class DependencyContext {
  const DependencyContext({
    required this.database,
    required this.apiBaseUrl,
    required this.apiClient,
    required this.sessionManager,
    required this.documentsDirectory,
  });

  /// The app's one SQLite database (`belog.sqlite`).
  final AppDatabase database;

  /// The validated API origin, without the `/api/v1` prefix.
  final Uri apiBaseUrl;

  /// The authenticated client every `/me` route goes through.
  final NowaveApiClient apiClient;

  /// The restored session; also the identity fence for account-scoped work.
  final NowaveSessionManager sessionManager;

  /// The app's documents folder; the publish queue keeps cover copies here.
  final Directory documentsDirectory;
}

/// Registers one feature's types on a container.
///
/// Every module only *registers*: factories and lazy singletons resolve their
/// collaborators when they are first asked for, never while the module runs.
/// That is what keeps the modules independent of each other's order -
/// `test/unit/di/app_modules_test.dart` registers them in reverse and still
/// resolves every type.
typedef DependencyModule =
    void Function(GetIt locator, DependencyContext context);
