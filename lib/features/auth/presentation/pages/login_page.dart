import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_gradient_button.dart';
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
        appBar: AppBar(),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthFailure) {
                  if (attemptedLogin) {
                    showSnackBar(context, state.message);
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
                        '登录',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),
                      AuthField(
                        hintText: "邮箱",
                        controller: emailController,
                        prefixIcon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 20),
                      AuthField(
                        hintText: "密码",
                        controller: passwordController,
                        isObscureText: true,
                        prefixIcon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 30),
                      AuthGradientButton(
                        buttonText: "登录",
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            attemptedLogin = true;
                            context.read<AuthBloc>().add(
                              AuthLogin(
                                email: emailController.text.trim(),
                                password: passwordController.text.trim(),
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
                        child: GestureDetector(
                          onTap: _openSignUp,
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              text: "没有账号？",
                              style: Theme.of(context).textTheme.titleMedium,
                              children: [
                                TextSpan(
                                  text: '注册',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .copyWith(
                                        color: AppPalette.gradient2,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('暂不登录，先去逛逛'),
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
