import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/presentation/password_validation_l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_frame.dart';
import 'package:belog/features/auth/presentation/widgets/auth_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

/// Account registration.
///
/// [redirectTo] is the in-app location the user was trying to open before
/// being redirected to the auth flow; a successful sign-up continues there.
/// The no-wave backend signs the user in immediately: there is no e-mail
/// confirmation step.
class SignUpPage extends StatefulWidget {
  final String? redirectTo;
  const SignUpPage({super.key, this.redirectTo});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  void _openLogin() {
    context.go(
      RoutePaths.withRedirect(
        RoutePaths.login,
        widget.redirectTo ?? RoutePaths.feed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppUserCubit, AppUserState>(
      listener: (context, state) {
        if (state is AppUserLoggedIn) {
          context.go(widget.redirectTo ?? '/');
        }
      },
      child: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthFailure) {
            // Only surface failures once the user has acted: the initial
            // cold-start restore must not toast noise.
            if (state.message.isNotEmpty) {
              showSnackBar(
                context,
                localizedFailure(context.l10n, state.failure),
              );
            }
          }
        },
        builder: (context, state) {
          final l10n = context.l10n;
          final busy = state is AuthLoading;
          return AuthFrame(
            title: l10n.signUpTitle,
            companion: l10n.signUpHeadingCompanion,
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthField(
                    hintText: l10n.fieldName,
                    controller: nameController,
                    enabled: !busy,
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
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
                    hintText: l10n.fieldPasswordWithMin,
                    controller: passwordController,
                    isObscureText: true,
                    enabled: !busy,
                    validator: (value) => passwordProblemMessage(
                      l10n,
                      validateNewPassword(value),
                    ),
                  ),
                  const SizedBox(height: NoWaveSpacing.section),
                  AuthPrimaryButton(
                    buttonText: l10n.submit,
                    isLoading: busy,
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        context.read<AuthBloc>().add(
                          AuthSignUp(
                            email: emailController.text.trim(),
                            name: nameController.text.trim(),
                            // Passwords are exact credentials, including
                            // any intentional leading/trailing spaces.
                            password: passwordController.text,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  AuthLink(
                    prompt: l10n.hasAccountPrompt,
                    label: l10n.signInLink,
                    onPressed: _openLogin,
                  ),
                  const SizedBox(height: NoWaveSpacing.section),
                  AuthLink(
                    label: l10n.browseWithoutSignUp,
                    quiet: true,
                    onPressed: () => context.go(RoutePaths.feed),
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
