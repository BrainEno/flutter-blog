import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';

/// Keeps [AppUserCubit] in sync with session events that happen outside
/// the AuthBloc-driven flows: most importantly a background refresh
/// failure, which revokes the session while the user is browsing and must
/// drop them out of the logged-in UI.
///
/// Pages must not have to restore side effects on their own: the cubit is
/// the single source of identity, and the router listens to it.
class AuthSessionSync {
  AuthSessionSync({
    required Stream<NowaveAuthStatus> statusStream,
    required NowaveSessionData? Function() currentSession,
    required CurrentUser currentUser,
    required AppUserCubit appUserCubit,
  }) : _statusStream = statusStream,
       _currentSession = currentSession,
       _currentUser = currentUser,
       _appUserCubit = appUserCubit;

  final Stream<NowaveAuthStatus> _statusStream;
  final NowaveSessionData? Function() _currentSession;
  final CurrentUser _currentUser;
  final AppUserCubit _appUserCubit;

  StreamSubscription<NowaveAuthStatus>? _subscription;
  bool _started = false;
  bool _refreshing = false;

  /// Starts listening. Idempotent so re-starting the app (tests) is safe.
  void start() {
    if (_started) return;
    _started = true;
    _subscription = _statusStream.listen(
      _onStatus,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'auth status stream failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Releases the subscription; safe to call multiple times.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<void> _onStatus(NowaveAuthStatus status) async {
    switch (status) {
      case NowaveAuthSignedOut():
        // Covers explicit sign-out on this device and sessions dropped
        // because a token refresh failed: without a session the user must
        // leave the logged-in UI.
        // A sign-out event can be delivered after a newer login. Never
        // clear the new account's UI state for the old account's event.
        if (_currentSession() == null) _appUserCubit.updateUser(null);
      case NowaveAuthSignedIn():
        await _refreshUser();
    }
  }

  Future<void> _refreshUser() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final res = await _currentUser(NoParams());
      res.fold(
        (failure) {
          AppLogger.debug('auth event user refresh failed: ${failure.code}');
        },
        (user) {
          // A refresh finishing after a sign-out must not resurrect the
          // logged-in state: only apply the user while the same session is
          // still current.
          final session = _currentSession();
          if (session != null && session.userId == user.id) {
            _appUserCubit.updateUser(user);
          }
        },
      );
    } finally {
      _refreshing = false;
    }
  }
}
