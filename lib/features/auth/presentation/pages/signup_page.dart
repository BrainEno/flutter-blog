import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_gradient_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
    final target = Uri.encodeComponent(widget.redirectTo ?? '/');
    context.go('/login?redirect=$target');
  }

  /// The backend enforces a 12-character minimum at registration (see
  /// docs/supabase-to-nowave-migration.md); checking it here keeps the
  /// error message localized and off the network.
  String? _validatePassword(AppLocalizations l10n, String? value) {
    if (value == null || value.isEmpty) {
      return l10n.passwordRequired;
    }
    if (value.length < 12) {
      return l10n.passwordMinLength;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppUserCubit, AppUserState>(
      listener: (context, state) {
        if (state is AppUserLoggedIn) {
          context.go(widget.redirectTo ?? '/');
        }
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthFailure) {
                  // Only surface failures once the user has acted: the
                  // initial cold-start restore must not toast noise.
                  if (state.message.isNotEmpty) {
                    showSnackBar(
                      context,
                      localizedFailure(context.l10n, state.failure),
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
                        context.l10n.signUpTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),
                      AuthField(
                        hintText: context.l10n.fieldName,
                        controller: nameController,
                        prefixIcon: Icons.person_outline,
                      ),
                      const SizedBox(height: 15),
                      AuthField(
                        hintText: context.l10n.fieldEmail,
                        controller: emailController,
                        prefixIcon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 15),
                      AuthField(
                        hintText: context.l10n.fieldPasswordWithMin,
                        controller: passwordController,
                        isObscureText: true,
                        prefixIcon: Icons.lock_outline,
                        validator: (value) =>
                            _validatePassword(context.l10n, value),
                      ),
                      const SizedBox(height: 30),
                      AuthGradientButton(
                        buttonText: context.l10n.submit,
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            context.read<AuthBloc>().add(
                              AuthSignUp(
                                email: emailController.text.trim(),
                                name: nameController.text.trim(),
                                password: passwordController.text.trim(),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 30),
                      Center(
                        child: TextButton(
                          onPressed: _openLogin,
                          child: Text(
                            '${context.l10n.hasAccountPrompt}${context.l10n.signInLink}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/'),
                        child: Text(context.l10n.browseWithoutSignUp),
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
