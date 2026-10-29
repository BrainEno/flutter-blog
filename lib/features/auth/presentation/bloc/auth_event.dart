part of 'auth_bloc.dart';

@immutable
sealed class AuthEvent {}

final class AuthIsUserLoggedIn extends AuthEvent {}

final class AuthSignUp extends AuthEvent {
  final String email;
  final String name;
  final String password;

  AuthSignUp({required this.email, required this.name, required this.password});
}

final class AuthLogin extends AuthEvent {
  final String email;
  final String password;

  AuthLogin({required this.email, required this.password});
}

final class AuthLogout extends AuthEvent {}

/// Re-sends the sign-up confirmation e-mail to [email].
final class AuthResendConfirmationEmail extends AuthEvent {
  final String email;

  AuthResendConfirmationEmail({required this.email});
}

/// Sends a password-recovery e-mail to [email].
final class AuthForgotPassword extends AuthEvent {
  final String email;

  AuthForgotPassword({required this.email});
}
