import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/auth_intent_gate.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/common/entities/user.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final UserSignUp _userSignUp;
  final UserLogin _userLogin;
  final CurrentUser _currentUser;
  final UserSignOut _userSignOut;
  final AppUserCubit _appUserCubit;
  final int Function() _sessionGeneration;
  final bool Function() _hasActiveSession;
  final bool Function(User) _isCurrentSessionUser;

  /// Orders sign-in, sign-up, sign-out and restore intents, so a slow older
  /// response cannot overwrite the account the user chose afterwards (#99).
  final AuthIntentGate _intentGate;

  AuthBloc({
    required UserSignUp userSignUp,
    required UserLogin userLogin,
    required UserSignOut userSignOut,
    required CurrentUser currentUser,
    required AppUserCubit appUserCubit,
    required int Function() sessionGeneration,
    required bool Function() hasActiveSession,
    required bool Function(User) isCurrentSessionUser,
    AuthIntentGate? intentGate,
  }) : _intentGate = intentGate ?? AuthIntentGate(),
       _userSignUp = userSignUp,
       _userLogin = userLogin,
       _userSignOut = userSignOut,
       _currentUser = currentUser,
       _appUserCubit = appUserCubit,
       _sessionGeneration = sessionGeneration,
       _hasActiveSession = hasActiveSession,
       _isCurrentSessionUser = isCurrentSessionUser,
       super(AuthInitial()) {
    // NOTE: there is deliberately no catch-all `on<AuthEvent>` handler.
    // Each handler below decides whether it emits [AuthLoading], so
    // background-ish events (restore) do not flip the whole auth UI into
    // a loader.
    on<AuthSignUp>(_onAuthSignUp);
    on<AuthLogin>(_onAuthLogin);
    on<AuthLogout>(_onAuthLogout);
    on<AuthIsUserLoggedIn>(_isUserLoggedIn);
  }

  Future<void> _onAuthSignUp(AuthSignUp event, Emitter<AuthState> emit) async {
    // Every attempt that can adopt a session takes the next intent id. The
    // id is taken synchronously, before any await, so it cannot be confused
    // with a newer attempt that starts while this one is in flight.
    final intent = _intentGate.begin();
    emit(AuthLoading());
    final res = await _userSignUp(
      UserSignUpParams(
        email: event.email,
        name: event.name,
        password: event.password,
        intent: intent,
      ),
    );
    // A newer intent owns the session, the cache and the UI now; this result
    // must not be replayed or reported as "never submitted" - the backend may
    // still have acted on the request that was sent.
    if (!_intentGate.isCurrent(intent)) return;

    res.fold(
      (failure) => emit(AuthFailure(failure.forPresentation())),
      // The backend signs the user in immediately: there is no e-mail
      // confirmation step anymore.
      (user) => _emitAuthSuccess(user, emit),
    );
  }

  Future<void> _onAuthLogin(AuthLogin event, Emitter<AuthState> emit) async {
    final intent = _intentGate.begin();
    emit(AuthLoading());
    // The data source resolves the full profile (GET /me + /me/profile)
    // as part of the login exchange, so the returned user is complete -
    // a second fetch here would only add a failure mode that signs the
    // user out of the UI even though the session is valid.
    final res = await _userLogin(
      UserLoginParams(
        email: event.email,
        password: event.password,
        intent: intent,
      ),
    );
    // The last attempt the user started wins, whatever the response order.
    if (!_intentGate.isCurrent(intent)) return;

    res.fold(
      (failure) => emit(AuthFailure(failure.forPresentation())),
      (user) => _emitAuthSuccess(user, emit),
    );
  }

  Future<void> _isUserLoggedIn(
    AuthIsUserLoggedIn event,
    Emitter<AuthState> emit,
  ) async {
    // A restore observes the current intent instead of taking a new one: an
    // explicit sign-in or sign-out that starts while it runs wins, while two
    // concurrent restores read the same session and cannot contradict each
    // other.
    final intent = _intentGate.current;
    final generation = _sessionGeneration();
    final res = await _currentUser(NoParams());
    if (_intentGate.current != intent) return;

    res.fold(
      (failure) {
        // A stale restore must not replace a newer account's UI state.
        if (_sessionGeneration() != generation &&
            failure.code == 'auth.sessionChanged') {
          return;
        }
        emit(AuthFailure(failure.forPresentation()));
      },
      (user) {
        if (_sessionGeneration() == generation) _emitAuthSuccess(user, emit);
      },
    );
  }

  Future<void> _onAuthLogout(AuthLogout event, Emitter<AuthState> emit) async {
    final intent = _intentGate.begin();
    emit(AuthLoading());
    final res = await _userSignOut(NoParams());
    // A sign-in that started after this sign-out owns the UI now; the session
    // it adopted must not be reported as a logout failure.
    if (!_intentGate.isCurrent(intent)) return;

    res.fold(
      (failure) {
        // Keep only a UI identity that still belongs to the active session.
        _discardStaleUser();
        emit(AuthLogoutFailure(failure.forPresentation()));
      },
      (_) {
        // A new login may arrive while per-account cleanup is still running.
        if (_hasActiveSession()) {
          _discardStaleUser();
          emit(
            AuthLogoutFailure(
              Failure(
                '登录账户已变更，请重试',
                kind: FailureKind.auth,
                code: 'auth.sessionChanged',
              ),
            ),
          );
          return;
        }
        _appUserCubit.updateUser(null);
        emit(AuthLogoutSuccess());
      },
    );
  }

  void _discardStaleUser() {
    final state = _appUserCubit.state;
    if (!_hasActiveSession() ||
        (state is AppUserLoggedIn && !_isCurrentSessionUser(state.user))) {
      _appUserCubit.updateUser(null);
    }
  }

  void _emitAuthSuccess(User user, Emitter<AuthState> emit) {
    // A newer session can replace the result between repository and UI.
    if (!_isCurrentSessionUser(user)) {
      _discardStaleUser();
      emit(
        AuthFailure(
          Failure(
            '登录账户已变更，请重试',
            kind: FailureKind.auth,
            code: 'auth.sessionChanged',
          ),
        ),
      );
      return;
    }
    _appUserCubit.updateUser(user);
    emit(AuthSuccess(user));
  }
}
