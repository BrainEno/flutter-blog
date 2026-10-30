part of 'auth_bloc.dart';

@immutable
sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthSuccess extends AuthState {
  final User user;

  const AuthSuccess(this.user);
}

final class AuthFailure extends AuthState {
  final Failure failure;

  const AuthFailure(this.failure);

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get message => failure.message;
}

final class AuthLogoutSuccess extends AuthState {}

final class AuthLogoutFailure extends AuthState {
  final Failure failure;

  const AuthLogoutFailure(this.failure);

  /// Display-safe Chinese fallback; the UI localizes via
  /// `localizedFailure` (issue #24).
  String get message => failure.message;
}
