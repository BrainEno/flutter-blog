import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps [AppUserCubit] in sync with Supabase auth events that happen
/// outside the AuthBloc-driven flows: token refreshes, e-mail confirmations
/// and password recovery arriving via deep links, and sessions invalidated
/// by refresh failures.
///
/// Pages must not have to restore side effects on their own: the cubit is
/// the single source of identity, and the router listens to it.
class AuthSessionSync {
  AuthSessionSync({
    required Stream<AuthState> authStateStream,
    required Session? Function() currentSession,
    required CurrentUser currentUser,
    required AppUserCubit appUserCubit,
  }) : _authStateStream = authStateStream,
       _currentSession = currentSession,
       _currentUser = currentUser,
       _appUserCubit = appUserCubit;

  final Stream<AuthState> _authStateStream;
  final Session? Function() _currentSession;
  final CurrentUser _currentUser;
  final AppUserCubit _appUserCubit;

  StreamSubscription<AuthState>? _subscription;
  bool _started = false;
  bool _refreshing = false;

  /// Starts listening. Idempotent so re-starting the app (tests) is safe.
  void start() {
    if (_started) return;
    _started = true;
    _subscription = _authStateStream.listen(
      _onAuthStateChange,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'auth state stream failed',
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

  Future<void> _onAuthStateChange(AuthState state) async {
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        // Covers explicit sign-out on this device and sessions dropped
        // because a token refresh failed: without a session the user must
        // leave the logged-in UI.
        _appUserCubit.updateUser(null);
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.passwordRecovery:
      case AuthChangeEvent.userUpdated:
        await _refreshUser();
      case AuthChangeEvent.tokenRefreshed:
        // The session was renewed but the identity did not change; the
        // cubit already holds the right user.
        break;
      default:
        // initialSession and platform-specific events are handled by the
        // startup restore in main() and need no sync here.
        break;
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
          if (session != null && session.user.id == user.id) {
            _appUserCubit.updateUser(user);
          }
        },
      );
    } finally {
      _refreshing = false;
    }
  }
}
