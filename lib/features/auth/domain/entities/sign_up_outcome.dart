import '../../../../core/common/entities/user.dart';

/// Outcome of a sign-up attempt.
///
/// Supabase may require e-mail confirmation before it creates a session.
/// When that happens there is no session yet: [user] is null and the UI
/// must ask the user to confirm their e-mail instead of treating them as
/// signed in. The auth user is never presented as a logged-in profile.
class SignUpOutcome {
  const SignUpOutcome({required this.email, this.user});

  /// Address the confirmation e-mail was sent to.
  final String email;

  /// Authenticated user; null while e-mail confirmation is pending.
  final User? user;

  bool get requiresEmailConfirmation => user == null;
}
