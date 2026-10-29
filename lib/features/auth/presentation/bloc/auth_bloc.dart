import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/usecase/usecase.dart';
import 'package:belog/features/auth/domain/usecases/current_user.dart';
import 'package:belog/features/auth/domain/usecases/resend_confirmation_email.dart';
import 'package:belog/features/auth/domain/usecases/send_password_reset_email.dart';
import 'package:belog/features/auth/domain/usecases/user_login.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_out.dart';
import 'package:belog/features/auth/domain/usecases/user_sign_up.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/common/entities/user.dart';
import '../../domain/entities/sign_up_outcome.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final UserSignUp _userSignUp;
  final UserLogin _userLogin;
  final CurrentUser _currentUser;
  final UserSignOut _userSignOut;
  final ResendConfirmationEmail _resendConfirmationEmail;
  final SendPasswordResetEmail _sendPasswordResetEmail;
  final AppUserCubit _appUserCubit;

  AuthBloc({
    required UserSignUp userSignUp,
    required UserLogin userLogin,
    required UserSignOut userSignOut,
    required CurrentUser currentUser,
    required ResendConfirmationEmail resendConfirmationEmail,
    required SendPasswordResetEmail sendPasswordResetEmail,
    required AppUserCubit appUserCubit,
  }) : _userSignUp = userSignUp,
       _userLogin = userLogin,
       _userSignOut = userSignOut,
       _currentUser = currentUser,
       _resendConfirmationEmail = resendConfirmationEmail,
       _sendPasswordResetEmail = sendPasswordResetEmail,
       _appUserCubit = appUserCubit,
       super(AuthInitial()) {
    // NOTE: there is deliberately no catch-all `on<AuthEvent>` handler.
    // Each handler below decides whether it emits [AuthLoading], so
    // background-ish events (resend e-mail, restore) do not flip the whole
    // auth UI into a loader.
    on<AuthSignUp>(_onAuthSignUp);
    on<AuthLogin>(_onAuthLogin);
    on<AuthLogout>(_onAuthLogout);
    on<AuthIsUserLoggedIn>(_isUserLoggedIn);
    on<AuthResendConfirmationEmail>(_onResendConfirmationEmail);
    on<AuthForgotPassword>(_onForgotPassword);
  }

  Future<void> _onAuthSignUp(AuthSignUp event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final res = await _userSignUp(
      UserSignUpParams(
        email: event.email,
        name: event.name,
        password: event.password,
      ),
    );

    res.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (outcome) => _emitSignUpOutcome(outcome, emit),
    );
  }

  void _emitSignUpOutcome(SignUpOutcome outcome, Emitter<AuthState> emit) {
    final user = outcome.user;
    if (user == null) {
      // Confirmation required: the user is NOT signed in yet, and the
      // auth user must not be presented as a logged-in profile.
      emit(AuthNeedsEmailConfirmation(outcome.email));
      return;
    }
    _emitAuthSuccess(user, emit);
  }

  Future<void> _onAuthLogin(AuthLogin event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    // Step 1: Perform login authentication
    final loginRes = await _userLogin(
      UserLoginParams(email: event.email, password: event.password),
    );

    // Check if login failed
    if (loginRes.isLeft()) {
      final failure = loginRes.fold((l) => l, (_) => null)!;
      emit(AuthFailure(failure.message));
      return;
    }

    // Login succeeded, proceed to fetch full user profile
    final currentUserRes = await _currentUser(NoParams());

    // Check if fetching user profile failed
    if (currentUserRes.isLeft()) {
      final failure = currentUserRes.fold((l) => l, (_) => null)!;
      emit(AuthFailure('Failed to fetch user profile: ${failure.message}'));
      return;
    }

    // Both operations succeeded, emit success
    final fullUser = currentUserRes.fold((_) => null, (r) => r)!;
    _emitAuthSuccess(fullUser, emit);
  }

  Future<void> _isUserLoggedIn(
    AuthIsUserLoggedIn event,
    Emitter<AuthState> emit,
  ) async {
    final res = await _currentUser(NoParams());

    res.fold((failure) => emit(AuthFailure(failure.message)), (user) {
      _emitAuthSuccess(user, emit);
    });
  }

  Future<void> _onAuthLogout(AuthLogout event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final res = await _userSignOut(NoParams());
    _appUserCubit.updateUser(null);

    res.fold(
      (failure) => emit(AuthLogoutFailure(failure.message)),
      (_) => emit(AuthLogoutSuccess()),
    );
  }

  Future<void> _onResendConfirmationEmail(
    AuthResendConfirmationEmail event,
    Emitter<AuthState> emit,
  ) async {
    // No AuthLoading: the sign-up page keeps its confirmation panel and
    // tracks the in-flight resend locally.
    final res = await _resendConfirmationEmail(event.email);
    res.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (_) => emit(const AuthConfirmationEmailSent()),
    );
  }

  Future<void> _onForgotPassword(
    AuthForgotPassword event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final res = await _sendPasswordResetEmail(event.email);
    res.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (_) => emit(const AuthPasswordResetEmailSent()),
    );
  }

  void _emitAuthSuccess(User user, Emitter<AuthState> emit) {
    _appUserCubit.updateUser(user);
    emit(AuthSuccess(user));
  }
}
