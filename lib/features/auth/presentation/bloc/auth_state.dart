part of 'auth_bloc.dart';

@immutable
sealed class AuthState {}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthSuccess extends AuthState {
  final User user;

  AuthSuccess(this.user);
}

final class AuthFailure extends AuthState {
  final String message;

  AuthFailure(this.message);
}

/// Sign-up succeeded but Supabase requires e-mail confirmation: there is
/// no session yet, so the user is not signed in.
final class AuthNeedsEmailConfirmation extends AuthState {
  final String email;

  AuthNeedsEmailConfirmation(this.email);
}

/// A re-sent sign-up confirmation e-mail is on its way.
final class AuthConfirmationEmailSent extends AuthState {
  const AuthConfirmationEmailSent();
}

/// A password-recovery e-mail is on its way.
final class AuthPasswordResetEmailSent extends AuthState {
  const AuthPasswordResetEmailSent();
}

final class AuthLogoutSuccess extends AuthState {}

final class AuthLogoutFailure extends AuthState {
  final String message;

  AuthLogoutFailure(this.message);
}
