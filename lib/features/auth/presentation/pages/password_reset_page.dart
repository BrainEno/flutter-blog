import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/auth/domain/password_recovery.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/domain/usecases/reset_password.dart';
import 'package:belog/features/auth/presentation/password_validation_l10n.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:belog/features/auth/presentation/widgets/auth_frame.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' show Either, left;
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

/// Redeems a copied one-time reset link or token. The token is sent only in
/// the body of an anonymous API request; it is never placed in a route or log.
class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.resetPassword,
    this.redirectTo,
  });

  final ResetPassword resetPassword;
  final String? redirectTo;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _resetting = false;
  bool _complete = false;
  bool _outcomeUnknown = false;
  Failure? _failure;

  @override
  void dispose() {
    _clearCredentials();
    _token.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _location(String path) =>
      RoutePaths.withRedirect(path, widget.redirectTo);

  void _backToSignIn() => context.go(_location(RoutePaths.login));

  void _requestAnotherLink() =>
      context.push(_location(RoutePaths.forgotPassword));

  String? _tokenProblem(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.passwordRecoveryTokenEmpty;
    }
    if (extractPasswordResetToken(value) == null) {
      return context.l10n.passwordRecoveryTokenMalformed;
    }
    return null;
  }

  void _clearCredentials() {
    _token.clear();
    _password.clear();
    _confirmPassword.clear();
  }

  Future<void> _submit() async {
    if (_resetting || _complete || _outcomeUnknown) return;
    if (!_formKey.currentState!.validate()) return;

    final token = extractPasswordResetToken(_token.text);
    if (token == null) return;
    final password = _password.text;
    _clearCredentials();
    FocusScope.of(context).unfocus();
    setState(() {
      _resetting = true;
      _failure = null;
    });

    Either<Failure, void> result;
    try {
      result = await widget.resetPassword(
        ResetPasswordParams(token: token, password: password),
      );
    } catch (_) {
      // The write may have committed before an unexpected failure surfaced.
      result = left(_resetOutcomeUnknown);
    }
    if (!mounted) return;
    setState(() {
      _resetting = false;
      result.fold(
        (failure) {
          _failure = failure.forPresentation();
          _outcomeUnknown =
              failure.code == 'auth.passwordRecoveryResetOutcomeUnknown';
        },
        (_) {
          _failure = null;
          _complete = true;
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = _failure;

    return AuthFrame(
      title: l10n.passwordRecoveryResetTitle,
      lead: l10n.passwordRecoveryResetInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            NoWaveNotice(
              message: localizedFailure(l10n, failure),
              tone: _outcomeUnknown
                  ? NoWaveNoticeTone.warning
                  : NoWaveNoticeTone.error,
              isLive: true,
            ),
            const SizedBox(height: NoWaveSpacing.large),
          ],
          if (_complete) ...[
            NoWaveNotice(
              message: l10n.passwordRecoveryResetSuccess,
              isLive: true,
            ),
            const SizedBox(height: NoWaveSpacing.large),
            NoWaveButton(
              label: l10n.passwordRecoveryBackToSignIn,
              onPressed: _backToSignIn,
              expand: true,
            ),
          ] else if (_outcomeUnknown) ...[
            NoWaveButton(
              label: l10n.passwordRecoveryBackToSignIn,
              onPressed: _backToSignIn,
              expand: true,
            ),
            const SizedBox(height: NoWaveSpacing.small),
            AuthLink(
              label: l10n.passwordRecoveryRequestAnotherLink,
              onPressed: _requestAnotherLink,
            ),
          ] else if (failure?.code == 'auth.passwordRecoveryUnsupported') ...[
            NoWaveButton(
              label: l10n.passwordRecoveryBackToSignIn,
              onPressed: _backToSignIn,
              expand: true,
            ),
          ] else ...[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthField(
                    hintText: l10n.passwordRecoveryTokenLabel,
                    controller: _token,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_resetting,
                    validator: _tokenProblem,
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  AuthField(
                    hintText: l10n.passwordRecoveryNewPassword,
                    controller: _password,
                    isObscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_resetting,
                    validator: (value) => passwordProblemMessage(
                      l10n,
                      validateNewPassword(value),
                    ),
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  AuthField(
                    hintText: l10n.passwordRecoveryConfirmPassword,
                    controller: _confirmPassword,
                    isObscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_resetting,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.passwordRequired;
                      }
                      if (value != _password.text) {
                        return l10n.passwordConfirmMismatch;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: NoWaveSpacing.large),
                  NoWaveButton(
                    label: _resetting
                        ? l10n.passwordRecoveryResetting
                        : l10n.passwordRecoveryReset,
                    onPressed: _resetting ? null : _submit,
                    isLoading: _resetting,
                    expand: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: NoWaveSpacing.small),
            AuthLink(
              label: l10n.passwordRecoveryRequestAnotherLink,
              onPressed: _requestAnotherLink,
            ),
            AuthLink(
              label: l10n.passwordRecoveryBackToSignIn,
              quiet: true,
              onPressed: _backToSignIn,
            ),
          ],
        ],
      ),
    );
  }
}

const _resetOutcomeUnknown = Failure(
  'The password reset result could not be confirmed.',
  kind: FailureKind.unknown,
  code: 'auth.passwordRecoveryResetOutcomeUnknown',
);
