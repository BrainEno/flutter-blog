import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/auth/domain/email_rules.dart';
import 'package:belog/features/auth/domain/usecases/request_password_reset.dart';
import 'package:belog/features/auth/presentation/auth_rhythm.dart';
import 'package:belog/features/auth/presentation/widgets/auth_field.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' show Either, left;
import 'package:go_router/go_router.dart';

/// Requests a password-reset link without revealing whether an address exists.
class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({
    super.key,
    required this.requestPasswordReset,
    this.redirectTo,
  });

  final RequestPasswordReset requestPasswordReset;
  final String? redirectTo;

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _accepted = false;
  Failure? _failure;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String _location(String path) {
    final target = widget.redirectTo;
    return target == null
        ? path
        : '$path?redirect=${Uri.encodeComponent(target)}';
  }

  void _openReset() => context.push(_location('/reset-password'));

  void _backToSignIn() => context.go(_location('/login'));

  String? _emailProblem(String? value) {
    final problem = validateEmailAddress(value);
    if (problem == null) return null;
    if (problem == EmailProblem.required) {
      return context.l10n.fieldRequiredPrompt(context.l10n.fieldEmail);
    }
    return context.l10n.passwordRecoveryEmailInvalid;
  }

  Future<void> _submit() async {
    if (_sending || _accepted) return;
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text;
    _email.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _failure = null;
    });

    Either<Failure, void> result;
    try {
      result = await widget.requestPasswordReset(
        RequestPasswordResetParams(email: email),
      );
    } catch (_) {
      // An unexpected error may follow a request that the server accepted.
      result = left(_requestOutcomeUnknown);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      result.fold(
        (failure) {
          _failure = failure.forPresentation();
          _accepted = false;
        },
        (_) {
          _failure = null;
          _accepted = true;
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = _failure;
    final mailDisabled =
        failure?.code == 'auth.passwordRecoveryMailDisabled';
    final unsupported = failure?.code == 'auth.passwordRecoveryUnsupported';
    final failureIsWarning =
        mailDisabled ||
        unsupported ||
        failure?.code == 'auth.passwordRecoveryRequestOutcomeUnknown';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.passwordRecoveryTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NoWaveSpacing.page),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AuthRhythm.title),
                  Text(
                    l10n.passwordRecoveryInfo,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: NoWaveSpacing.large),
                  if (_accepted) ...[
                    NoWaveNotice(
                      message: l10n.passwordRecoveryRequestAccepted,
                      isLive: true,
                    ),
                    const SizedBox(height: NoWaveSpacing.large),
                    NoWaveButton(
                      label: l10n.passwordRecoveryAlreadyHaveLink,
                      onPressed: _openReset,
                      expand: true,
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    TextButton(
                      onPressed: _backToSignIn,
                      child: Text(l10n.passwordRecoveryBackToSignIn),
                    ),
                  ] else if (mailDisabled || unsupported) ...[
                    NoWaveNotice(
                      message: localizedFailure(l10n, failure!),
                      tone: NoWaveNoticeTone.warning,
                      isLive: true,
                    ),
                    const SizedBox(height: NoWaveSpacing.large),
                    if (mailDisabled) ...[
                      NoWaveButton(
                        label: l10n.passwordRecoveryAlreadyHaveLink,
                        onPressed: _openReset,
                        expand: true,
                      ),
                      const SizedBox(height: NoWaveSpacing.small),
                    ],
                    TextButton(
                      onPressed: _backToSignIn,
                      child: Text(l10n.passwordRecoveryBackToSignIn),
                    ),
                  ] else ...[
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthField(
                            hintText: l10n.fieldEmail,
                            controller: _email,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            enabled: !_sending,
                            validator: _emailProblem,
                          ),
                          const SizedBox(height: NoWaveSpacing.large),
                          if (failure != null) ...[
                            NoWaveNotice(
                              message: localizedFailure(l10n, failure),
                              tone: failureIsWarning
                                  ? NoWaveNoticeTone.warning
                                  : NoWaveNoticeTone.error,
                              isLive: true,
                            ),
                            const SizedBox(height: NoWaveSpacing.medium),
                          ],
                          NoWaveButton(
                            label: _sending
                                ? l10n.passwordRecoverySending
                                : l10n.passwordRecoverySend,
                            onPressed: _sending ? null : _submit,
                            isLoading: _sending,
                            expand: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: NoWaveSpacing.small),
                    TextButton(
                      onPressed: _openReset,
                      child: Text(l10n.passwordRecoveryAlreadyHaveLink),
                    ),
                    TextButton(
                      onPressed: _backToSignIn,
                      child: Text(l10n.passwordRecoveryBackToSignIn),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _requestOutcomeUnknown = Failure(
  'The recovery request result could not be confirmed.',
  kind: FailureKind.unknown,
  code: 'auth.passwordRecoveryRequestOutcomeUnknown',
);
