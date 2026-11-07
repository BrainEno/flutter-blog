import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/common/widgets/language_menu_button.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Email/password sign-in.
///
/// [redirectTo] is the in-app location the user was trying to open before
/// being redirected here; after a successful sign-in the app returns to it.
class LoginPage extends StatefulWidget {
  final String? redirectTo;
  const LoginPage({super.key, this.redirectTo});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  /// Set once the user actually tries to sign in, so the cold-start
  /// restore check (dispatched in initState) does not surface a
  /// "请登录账户" snackbar on every visit.
  bool attemptedLogin = false;

  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add(AuthIsUserLoggedIn());
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// The diagnostics dialog, opened from the failed-login snackbar.
  void _openDiagnostics() => context.push('/about?diagnostics=1');

  void _openSignUp() {
    final target = Uri.encodeComponent(widget.redirectTo ?? '/');
    context.push('/signup?redirect=$target');
  }

  void _onAuthenticated() {
    // The router's redirect also re-runs on auth changes; going explicitly
    // keeps the return-to-location behaviour deterministic.
    context.go(widget.redirectTo ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppUserCubit, AppUserState>(
      listener: (context, state) {
        if (state is AppUserLoggedIn) {
          _onAuthenticated();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          actions: const [
            LanguageMenuButton(),
            SizedBox(width: NoWaveSpacing.small),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthFailure) {
                  if (attemptedLogin) {
                    final failure = state.failure;
                    // A transport failure is the case where the diagnostics
                    // report actually answers the question: make it one tap
                    // away instead of hoping the user finds the About page.
                    final offerDiagnostics =
                        failure.kind == FailureKind.network ||
                        failure.kind == FailureKind.timeout;
                    showSnackBar(
                      context,
                      localizedFailure(context.l10n, failure),
                      action: offerDiagnostics
                          ? SnackBarAction(
                              label: context.l10n.diagnosticsEntry,
                              onPressed: _openDiagnostics,
                            )
                          : null,
                    );
                  }
                }
              },
              builder: (context, state) {
                if (state is AuthLoading) {
                  return const Loader();
                }
                return Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      Text(
                        context.l10n.loginTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),
                      AuthField(
                        hintText: context.l10n.fieldEmail,
                        controller: emailController,
                        prefixIcon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 20),
                      AuthField(
                        hintText: context.l10n.fieldPassword,
                        controller: passwordController,
                        isObscureText: true,
                        prefixIcon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 30),
                      AuthPrimaryButton(
                        buttonText: context.l10n.loginTitle,
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            attemptedLogin = true;
                            context.read<AuthBloc>().add(
                              AuthLogin(
                                email: emailController.text.trim(),
                                // Match no-wave's exact password semantics.
                                password: passwordController.text,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // No "forgot password" entry: the backend has no
                      // password-reset flow yet (gap G2, see
                      // docs/supabase-to-nowave-migration.md).
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton(
                          onPressed: _openSignUp,
                          child: Text(
                            '${context.l10n.noAccountPrompt}${context.l10n.signUpLink}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/'),
                        child: Text(context.l10n.browseWithoutSignIn),
                      ),
                      // Public entry: signing in is exactly when the report
                      // is needed, so it must not hide behind the profile tab.
                      TextButton(
                        onPressed: () => context.push('/about'),
                        child: Text(context.l10n.diagnosticsEntry),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
