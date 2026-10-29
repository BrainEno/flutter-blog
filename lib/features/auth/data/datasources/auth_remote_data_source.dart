import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/auth/auth_constants.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/auth/domain/entities/sign_up_outcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthRemoteDataSource {
  Session? get currentUserSession;

  Future<SignUpOutcome> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  });

  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
  });

  Future<UserModel?> getCurrentUserData();

  /// Re-sends the sign-up confirmation e-mail for [email].
  Future<void> resendConfirmationEmail(String email);

  /// Sends a password-recovery e-mail for [email]; the link inside opens
  /// the app via [kAuthCallbackUrl].
  Future<void> sendPasswordResetEmail(String email);

  Future<void> logout();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient supabaseClient;
  AuthRemoteDataSourceImpl(this.supabaseClient);

  @override
  Session? get currentUserSession => supabaseClient.auth.currentSession;

  @override
  Future<UserModel?> getCurrentUserData() async {
    try {
      final session = currentUserSession;
      if (session == null) {
        return null;
      }
      // A valid session without a profile row means the server-side
      // profile trigger has not produced (or no longer has) a profile.
      // Report "no profile" instead of crashing, and let the caller decide
      // how to treat it - the auth user is never fabricated into a
      // logged-in profile.
      final userData = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', session.user.id)
          .maybeSingle();
      if (userData == null) {
        return null;
      }
      return UserModel.fromJson(userData).copyWith(email: session.user.email);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<UserModel> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabaseClient.auth.signInWithPassword(
        password: password,
        email: email,
      );
      if (response.user == null) {
        throw ServerException("User is null!");
      }
      return UserModel.fromJson(response.user!.toJson());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<SignUpOutcome> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabaseClient.auth.signUp(
        password: password,
        email: email,
        emailRedirectTo: kAuthCallbackUrl,
        data: {'name': name},
      );
      final authUser = response.user;
      if (authUser == null) {
        throw ServerException("User is null!");
      }
      if (response.session == null) {
        // E-mail confirmation is required: no session exists, so the user
        // is NOT signed in yet.
        return SignUpOutcome(email: authUser.email ?? email);
      }
      // A session exists (confirmation disabled or already satisfied).
      // This is an auth-level identity only - the full profile is fetched
      // separately and refreshed through the auth state sync.
      return SignUpOutcome(
        email: authUser.email ?? email,
        user: UserModel(
          id: authUser.id,
          email: authUser.email ?? email,
          name: name,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> resendConfirmationEmail(String email) async {
    try {
      await supabaseClient.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kAuthCallbackUrl,
      );
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await supabaseClient.auth.resetPasswordForEmail(
        email,
        redirectTo: kAuthCallbackUrl,
      );
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> logout() async {
    try {
      await supabaseClient.auth.signOut();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
