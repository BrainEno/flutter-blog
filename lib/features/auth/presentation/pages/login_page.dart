import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_frame.dart';
import 'package:belog/features/auth/presentation/widgets/auth_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

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
  void _openDiagnostics() => context.push(RoutePaths.aboutDiagnostics);

  void _openSignUp() {
    context.push(
      RoutePaths.withRedirect(
        RoutePaths.signup,
        widget.redirectTo ?? RoutePaths.feed,
      ),
    );
  }

  void _openPasswordRecovery() {
    context.push(
      RoutePaths.withRedirect(
        RoutePaths.forgotPassword,
        widget.redirectTo ?? RoutePaths.feed,
      ),
    );
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
          final l10n = context.l10n;
          final busy = state is AuthLoading;
          return AuthFrame(
            title: l10n.loginTitle,
            companion: l10n.loginHeadingCompanion,
            languageMenu: true,
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthField(
                    hintText: l10n.fieldEmail,
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !busy,
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  AuthField(
                    hintText: l10n.fieldPassword,
                    controller: passwordController,
                    isObscureText: true,
                    enabled: !busy,
                  ),
                  // Right under the password line, centred like every other
                  // small link on the page so the form has one axis.
                  AuthLink(
                    label: l10n.passwordRecoveryTitle,
                    onPressed: _openPasswordRecovery,
                  ),
                  const SizedBox(height: NoWaveSpacing.large),
                  AuthPrimaryButton(
                    buttonText: l10n.loginTitle,
                    isLoading: busy,
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
                  const SizedBox(height: NoWaveSpacing.medium),
                  AuthLink(
                    prompt: l10n.noAccountPrompt,
                    label: l10n.signUpLink,
                    onPressed: _openSignUp,
                  ),
                  const SizedBox(height: NoWaveSpacing.section),
                  // The ways out that are not signing in: quieter, together,
                  // after the form is done.
                  AuthLink(
                    label: l10n.browseWithoutSignIn,
                    quiet: true,
                    onPressed: () => context.go(RoutePaths.feed),
                  ),
                  // Public entry: signing in is exactly when the report is
                  // needed, so it must not hide behind the profile tab.
                  AuthLink(
                    label: l10n.diagnosticsEntry,
                    quiet: true,
                    onPressed: () => context.push(RoutePaths.about),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
