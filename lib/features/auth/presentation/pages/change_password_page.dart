import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/features/auth/domain/password_rules.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/features/auth/presentation/password_validation_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' show Either, left;

/// A form is bound to the identity and session that were active on opening.
/// Credentials live only in the controllers and the in-flight request; they
/// never enter a bloc state, a diagnostic failure, or local persistence.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.repository,
    required this.session,
  });

  final AccountSecurityRepository repository;
  final NowaveViewerAuthenticator session;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  late final String _userId;
  late final int _generation;
  bool _accountChanged = false;
  bool _busy = false;
  bool _success = false;
  bool _showCurrent = false;
  bool _showNext = false;
  bool _showConfirm = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppUserCubit>().state;
    _userId = state is AppUserLoggedIn ? state.user.id : '';
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

  void _clearCredentials() {
    _current.clear();
    _next.clear();
    _confirm.clear();
    _showCurrent = false;
    _showNext = false;
    _showConfirm = false;
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _accountChanged) return;
    if (!_sameSession()) {
      _clearCredentials();
      setState(() {
        _accountChanged = true;
        _failure = _sessionChanged;
        _success = false;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final currentPassword = _current.text;
    final newPassword = _next.text;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
      _success = false;
    });

    Either<Failure, void> result;
    try {
      result = await widget.repository.changePassword(
        expectedUserId: _userId,
        expectedSessionGeneration: _generation,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } catch (_) {
      // An unexpected failure can also happen after a write was sent. Never
      // retain or render the exception, which could contain request data.
      result = left(_outcomeUnknown);
    }
    if (!mounted) return;
    _clearCredentials();
    if (!_sameSession()) {
      setState(() {
        _busy = false;
        _accountChanged = true;
        _failure = _sessionChanged;
      });
      return;
    }
    setState(() {
      _busy = false;
      result.fold(
        (failure) => _failure = failure.forPresentation(),
        (_) => _success = true,
      );
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
            _success = false;
            _failure = _sessionChanged;
          });
        }
      },
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.passwordChangeTitle)),
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
                          Text(l10n.passwordChangeInfo),
                          const SizedBox(height: 12),
                          Text(l10n.passwordChangeRules),
                          const SizedBox(height: 24),
                          _passwordField(
                            label: l10n.passwordCurrent,
                            controller: _current,
                            visible: _showCurrent,
                            enabled: enabled,
                            onToggle: () =>
                                setState(() => _showCurrent = !_showCurrent),
                            validator: (value) => passwordProblemMessage(
                              l10n,
                              validateCurrentPassword(value),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _passwordField(
                            label: l10n.passwordNew,
                            controller: _next,
                            visible: _showNext,
                            enabled: enabled,
                            onToggle: () =>
                                setState(() => _showNext = !_showNext),
                            validator: (value) => passwordProblemMessage(
                              l10n,
                              validateNewPassword(value),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _passwordField(
                            label: l10n.passwordConfirm,
                            controller: _confirm,
                            visible: _showConfirm,
                            enabled: enabled,
                            onToggle: () =>
                                setState(() => _showConfirm = !_showConfirm),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l10n.passwordRequired;
                              }
                              if (value != _next.text) {
                                return l10n.passwordConfirmMismatch;
                              }
                              return null;
                            },
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
                          if (_success) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(l10n.passwordChangeSuccess),
                            ),
                            const SizedBox(height: 16),
                          ],
                          FilledButton(
                            onPressed: enabled ? _submit : null,
                            child: Text(
                              _busy
                                  ? l10n.passwordChanging
                                  : l10n.passwordChangeAction,
                            ),
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

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required bool enabled,
    required VoidCallback onToggle,
    required FormFieldValidator<String> validator,
  }) {
    final l10n = context.l10n;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: visible
              ? l10n.passwordHideField(label)
              : l10n.passwordShowField(label),
          onPressed: enabled ? onToggle : null,
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }
}

const _sessionChanged = Failure(
  '登录账户已变更；操作可能已针对原账户完成，请先确认',
  kind: FailureKind.auth,
  code: 'auth.sessionChanged',
);
const _outcomeUnknown = Failure(
  '无法确认修改结果：密码可能已更改，其他设备仍可能保持登录。请先用新密码登录确认',
  kind: FailureKind.unknown,
  code: 'auth.passwordOutcomeUnknown',
);
