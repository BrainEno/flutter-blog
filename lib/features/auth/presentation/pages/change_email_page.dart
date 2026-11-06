import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/domain/email_rules.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/password_validation_l10n.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' show Either, left;

/// Moves the signed-in account to another address.
///
/// Same shape as [ChangePasswordPage]: the form is bound to the identity and
/// session that opened it, the password lives only in the controller and the
/// in-flight request, and a write whose outcome is unknown is never retried by
/// the app on the reader's behalf.
class ChangeEmailPage extends StatefulWidget {
  const ChangeEmailPage({
    super.key,
    required this.repository,
    required this.session,
  });

  final AccountSecurityRepository repository;
  final NowaveViewerAuthenticator session;

  @override
  State<ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<ChangeEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final String _userId;
  late final int _generation;
  late String _currentEmail;
  bool _accountChanged = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _storedEmail;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppUserCubit>().state;
    _userId = state is AppUserLoggedIn ? state.user.id : '';
    _currentEmail = state is AppUserLoggedIn ? state.user.email : '';
    _generation = widget.session.sessionGeneration;
    _accountChanged = !_sameSession(state);
    if (_accountChanged) _failure = _sessionChanged;
  }

  bool _sameSession([AppUserState? userState]) {
    final state = userState ?? context.read<AppUserCubit>().state;
    return state is AppUserLoggedIn &&
        _userId.isNotEmpty &&
        state.user.id == _userId &&
        widget.session.activeUserId == _userId &&
        widget.session.sessionGeneration == _generation &&
        (widget.session.accessToken?.isNotEmpty ?? false);
  }

  /// The password is a secret: it never outlives one attempt.
  void _clearPassword() {
    _password.clear();
    _showPassword = false;
  }

  /// Used when the page stops belonging to an account: nothing typed in it may
  /// be reused.
  void _clearCredentials() {
    _clearPassword();
    _email.clear();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _accountChanged) return;
    if (!_sameSession()) {
      _clearCredentials();
      setState(() {
        _accountChanged = true;
        _failure = _sessionChanged;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final next = normalizeEmailAddress(_email.text);
    // After a successful change the account already holds the stored address,
    // so a repeat submit is refused here too instead of costing a password
    // check.
    final unchanged =
        _currentEmail.isNotEmpty &&
        next == normalizeEmailAddress(_currentEmail);
    if (unchanged) {
      // The server answers this as a no-op, but it still costs a password
      // check: say what is true before asking.
      setState(() {
        _failure = _unchanged;
        _storedEmail = null;
      });
      return;
    }
    final currentPassword = _password.text;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
      _storedEmail = null;
    });

    Either<Failure, String> result;
    try {
      result = await widget.repository.changeEmail(
        expectedUserId: _userId,
        expectedSessionGeneration: _generation,
        currentPassword: currentPassword,
        newEmail: next,
      );
    } catch (_) {
      // Something unexpected can also happen after the write was sent; never
      // keep or render the exception, which may contain request data.
      result = left(_outcomeUnknown);
    }
    if (!mounted) return;
    // The address stays so a refused change can be corrected without retyping;
    // only the password has to be entered again.
    _clearPassword();
    if (!_sameSession()) {
      _clearCredentials();
      setState(() {
        _busy = false;
        _accountChanged = true;
        _failure = _sessionChanged;
      });
      return;
    }
    setState(() {
      _busy = false;
      result.fold((failure) => _failure = failure.forPresentation(), (email) {
        _storedEmail = email;
        _currentEmail = email;
        _email.clear();
        // The account object carries the address the rest of the app shows;
        // the server is the one that decided its final form.
        final state = context.read<AppUserCubit>().state;
        if (state is AppUserLoggedIn) {
          final user = state.user;
          context.read<AppUserCubit>().updateUser(
            User(
              id: user.id,
              email: email,
              name: user.name,
              bio: user.bio,
              avatarUrl: user.avatarUrl,
              website: user.website,
              updatedAt: user.updatedAt,
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = !_busy && !_accountChanged;
    return BlocListener<AppUserCubit, AppUserState>(
      listener: (context, state) {
        if (!_accountChanged && !_sameSession(state)) {
          _clearCredentials();
          setState(() {
            _accountChanged = true;
            _storedEmail = null;
            _failure = _sessionChanged;
          });
        }
      },
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.accountEmailTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.accountEmailInfo),
                          const SizedBox(height: 24),
                          if (_currentEmail.isEmpty)
                            Text(
                              l10n.accountEmailMissingCurrent,
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else ...[
                            Text(
                              l10n.accountEmailCurrent,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            // A separate line rather than a glued label, so the
                            // address is what assistive tech reads out in any
                            // language and scripts stay free of punctuation
                            // rules.
                            Text(
                              _currentEmail,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _email,
                            enabled: enabled,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            validator: (value) =>
                                _emailProblemMessage(l10n, value),
                            decoration: InputDecoration(
                              labelText: l10n.accountEmailNew,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            enabled: enabled,
                            obscureText: !_showPassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            validator: (value) => passwordProblemMessage(
                              l10n,
                              validateCurrentPassword(value),
                            ),
                            decoration: InputDecoration(
                              labelText: l10n.passwordCurrent,
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? l10n.passwordHideField(
                                        l10n.passwordCurrent,
                                      )
                                    : l10n.passwordShowField(
                                        l10n.passwordCurrent,
                                      ),
                                onPressed: enabled
                                    ? () => setState(
                                        () => _showPassword = !_showPassword,
                                      )
                                    : null,
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_failure != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                localizedFailure(l10n, _failure!),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_storedEmail != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.accountEmailSuccess(_storedEmail!)),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.accountEmailUnverified,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          NoWaveButton(
                            label: _busy
                                ? l10n.accountEmailUpdating
                                : l10n.accountEmailAction,
                            onPressed: enabled ? _submit : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The inline message for a rejected address, or null when it is fine.
  String? _emailProblemMessage(AppLocalizations l10n, String? value) {
    return switch (validateEmailAddress(value)) {
      null => null,
      EmailProblem.required => l10n.accountEmailRequired,
      EmailProblem.tooLong => l10n.accountEmailTooLong,
      EmailProblem.malformed => l10n.accountEmailInvalid,
    };
  }
}

const _sessionChanged = Failure(
  '登录账户已变更；操作可能已针对原账户完成，请先确认',
  kind: FailureKind.auth,
  code: 'auth.sessionChanged',
);
const _outcomeUnknown = Failure(
  '无法确认修改结果：邮箱可能已变更。请稍后打开「修改邮箱」核对当前地址，勿立即重复提交。',
  kind: FailureKind.unknown,
  code: 'account.emailOutcomeUnknown',
);
const _unchanged = Failure(
  '新邮箱与当前邮箱相同，无需修改',
  kind: FailureKind.validation,
  code: 'account.emailUnchanged',
);
