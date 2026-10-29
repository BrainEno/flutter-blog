import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/loader.dart';
import 'package:belog/core/theme/app_pallete.dart';
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
///
/// When Supabase requires e-mail confirmation the page switches to a
/// confirmation-pending panel: the user is NOT signed in until they click
/// the link in the e-mail, which opens the app through the auth deep link.
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

  /// Address awaiting confirmation; non-null while the confirmation panel
  /// is showing. Kept locally so background auth states (loading, resend
  /// results) do not flip the page back to the sign-up form.
  String? pendingConfirmationEmail;

  /// Whether a re-send request is in flight, for the button spinner.
  bool resending = false;

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

  void _resendConfirmation() {
    final email = pendingConfirmationEmail;
    if (email == null || resending) return;
    setState(() => resending = true);
    context.read<AuthBloc>().add(
          AuthResendConfirmationEmail(email: email),
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
      child: Scaffold(
        appBar: AppBar(),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthNeedsEmailConfirmation) {
                  pendingConfirmationEmail = state.email;
                } else if (state is AuthConfirmationEmailSent) {
                  setState(() => resending = false);
                  showSnackBar(context, '确认邮件已重新发送，请查收');
                } else if (state is AuthFailure) {
                  if (resending) {
                    setState(() => resending = false);
                  }
                  // Only surface failures once the user has acted: the
                  // initial cold-start restore must not toast noise.
                  if (pendingConfirmationEmail != null ||
                      state.message.isNotEmpty) {
                    showSnackBar(context, state.message);
                  }
                }
              },
              builder: (context, state) {
                if (state is AuthLoading) {
                  return const Loader();
                }

                if (pendingConfirmationEmail != null) {
                  return _ConfirmationPendingPanel(
                    email: pendingConfirmationEmail!,
                    resending: resending,
                    onResend: _resendConfirmation,
                    onBackToLogin: _openLogin,
                  );
                }

                return Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Text(
                          '注册',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        AuthField(
                          hintText: "用户名",
                          controller: nameController,
                          prefixIcon: Icons.person_outline,
                        ),
                        const SizedBox(height: 15),
                        AuthField(
                          hintText: "邮箱",
                          controller: emailController,
                          prefixIcon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 15),
                        AuthField(
                          hintText: "密码",
                          controller: passwordController,
                          isObscureText: true,
                          prefixIcon: Icons.lock_outline,
                        ),
                        const SizedBox(height: 30),
                        AuthGradientButton(
                          buttonText: '提交',
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
                          child: GestureDetector(
                            onTap: _openLogin,
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                text: "已有账号？",
                                style: Theme.of(context).textTheme.titleMedium,
                                children: [
                                  TextSpan(
                                    text: '登录',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .copyWith(
                                          color: AppPallete.gradient2,
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
                          child: const Text('暂不注册，先去逛逛'),
                        ),
                        const SizedBox(height: 60),
                      ],
                    ),
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

/// Shown after a sign-up that requires e-mail confirmation. The user is
/// not signed in at this point; the deep link in the e-mail completes the
/// flow and logs them in.
class _ConfirmationPendingPanel extends StatelessWidget {
  final String email;
  final bool resending;
  final VoidCallback onResend;
  final VoidCallback onBackToLogin;

  const _ConfirmationPendingPanel({
    required this.email,
    required this.resending,
    required this.onResend,
    required this.onBackToLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.mark_email_read_outlined,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          '请确认邮箱',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          '注册成功！我们已向 $email 发送确认邮件，'
          '请查收并点击邮件中的链接完成注册。点击链接后会自动返回应用并登录。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: resending ? null : onResend,
          icon: resending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(resending ? '发送中…' : '重新发送确认邮件'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onBackToLogin,
          child: const Text('返回登录'),
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}
