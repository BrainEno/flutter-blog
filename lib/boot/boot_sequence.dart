import 'dart:async';

import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/auth_session_sync.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/publish/publish_queue_service.dart';
import 'package:belog/init_dependencies.dart';

/// How long the cold-start session restore may hold back the app.
///
/// Normally the restore resolves in well under a second; the bound only guards
/// against a hung network so the app still becomes usable.
const _kSessionRestoreTimeout = Duration(seconds: 3);

/// The language preference is one small row; it resolves instantly in normal
/// boots. Bounding it only keeps a corrupt store from delaying the app.
const _kLanguageRestoreTimeout = Duration(seconds: 2);

/// Everything the app needs before its first route can be built.
///
/// This used to sit inside `main()` *before* `runApp()`, which meant the
/// operating system kept showing its static launch image for as long as the
/// waits took - up to five seconds on a slow cold start. It now runs inside the
/// running app, while the curtain is on screen: same work, same bounds, but the
/// user sees the brand instead of a frozen icon.
///
/// It throws when the injector cannot be built (missing or invalid
/// `API_BASE_URL`, unreadable storage). The caller renders that failure; the
/// rest of the steps degrade to debug logs because a slow network must not stop
/// the app from starting.
Future<void> runBootSequence() async {
  await initDependencies();

  // Apply the saved interface choice before the first route is built (#108).
  // The feed dispatches its first request while building, and that request
  // reads the content language from the same holder this bloc updates:
  // resolving it now means the first page is never fetched in one language and
  // re-fetched in the other.
  try {
    await serviceLocator<LocaleBloc>().initialized.timeout(
      _kLanguageRestoreTimeout,
    );
  } on TimeoutException {
    AppLogger.debug('language restore timed out; continuing boot');
  }

  // Restore the persisted no-wave session before the first route, so the
  // router's auth redirect and tab visibility see the correct user state
  // instead of a logged-out flash. The wait is bounded: a slow network must not
  // keep the app from starting, and the login page re-checks on entry as a
  // backstop.
  final authBloc = serviceLocator<AuthBloc>();
  authBloc.add(AuthIsUserLoggedIn());
  try {
    await authBloc.stream
        .firstWhere(
          (state) =>
              state is AuthSuccess ||
              state is AuthFailure ||
              state is AuthLogoutFailure,
        )
        .timeout(_kSessionRestoreTimeout);
  } on TimeoutException {
    AppLogger.debug('session restore timed out; continuing boot');
  }

  // Keep the app-wide identity cubit in sync with out-of-band session events
  // (a failed background token refresh drops the session).
  serviceLocator<AuthSessionSync>().start();

  // Publish queue (issue #23): repair what a killed process left behind and
  // send anything the previous session could not. It does nothing while no
  // account is signed in, and it is not awaited: boot must not wait for the
  // network.
  unawaited(serviceLocator<PublishQueueService>().start());
}
