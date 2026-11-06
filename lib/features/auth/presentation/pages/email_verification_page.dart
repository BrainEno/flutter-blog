import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/auth/domain/email_verification.dart';
import 'package:belog/features/auth/domain/repository/account_security_repository.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// States whether the account's address is verified, and offers the two ways to
/// change that.
///
/// Verification is never a condition for anything else in the app, so this
/// screen only reports a fact: the server's `emailVerifiedAt`. The mailed link
/// points at the web front end, which the app cannot claim, so the completion
/// paths are "confirm in the browser, then refresh" and, when that is not
/// possible, pasting the link or code here.
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    required this.repository,
    required this.session,
  });

  final AccountSecurityRepository repository;
  final NowaveViewerAuthenticator session;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _token = TextEditingController();
  late final String _userId;
  late final int _generation;
  bool _accountChanged = false;
  bool _loadingStatus = false;
  bool _sending = false;
  bool _confirming = false;
  int _loadVersion = 0;
  AccountEmailStatus? _status;
  Failure? _statusFailure;
  Failure? _sendFailure;
  EmailVerificationRequest? _request;
  Failure? _confirmFailure;
  bool _confirmed = false;
  String? _tokenProblem;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppUserCubit>().state;
    _userId = state is AppUserLoggedIn ? state.user.id : '';
    _generation = widget.session.sessionGeneration;
    _accountChanged = !_sameSession(state);
    if (!_accountChanged) unawaited(_readStatus());
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

  void _lock() {
    if (!mounted || _accountChanged) return;
    _token.clear();
    _loadVersion++;
    setState(() {
      _accountChanged = true;
      _loadingStatus = false;
      _sending = false;
      _confirming = false;
      _status = null;
      _statusFailure = null;
      _sendFailure = null;
      _request = null;
      _confirmFailure = null;
      _confirmed = false;
      _tokenProblem = null;
    });
  }

  Future<void> _readStatus() async {
    if (_loadingStatus || _accountChanged) return;
    if (!_sameSession()) {
      _lock();
      return;
    }
    final version = ++_loadVersion;
    setState(() {
      _loadingStatus = true;
      _statusFailure = null;
    });
    try {
      final result = await widget.repository.readEmailStatus(
        expectedUserId: _userId,
        expectedSessionGeneration: _generation,
      );
      if (!mounted || version != _loadVersion || !_sameSession()) return;
      setState(() {
        _loadingStatus = false;
        result.fold(
          (failure) => _statusFailure = failure.forPresentation(),
          (status) => _status = status,
        );
      });
    } catch (_) {
      if (!mounted || version != _loadVersion || !_sameSession()) return;
      // The repository returns typed failures; anything else is not rendered.
      setState(() {
        _loadingStatus = false;
        _statusFailure = _statusUnavailable;
      });
    }
  }

  Future<void> _send() async {
    if (_sending || _accountChanged) return;
    if (!_sameSession()) {
      _lock();
      return;
    }
    setState(() {
      _sending = true;
      _sendFailure = null;
      _request = null;
    });
    try {
      final result = await widget.repository.requestEmailVerification(
        expectedUserId: _userId,
        expectedSessionGeneration: _generation,
      );
      if (!mounted) return;
      if (!_sameSession()) {
        _lock();
        return;
      }
      setState(() {
        _sending = false;
        result.fold(
          (failure) => _sendFailure = failure.forPresentation(),
          (request) => _request = request,
        );
      });
      // "Already verified" means the screen is showing a stale fact.
      if (_request == EmailVerificationRequest.alreadyVerified) {
        await _readStatus();
      }
    } catch (_) {
      if (!mounted) return;
      if (!_sameSession()) {
        _lock();
        return;
      }
      setState(() {
        _sending = false;
        // The mail may already have gone out; never invite a blind retry.
        _sendFailure = _outcomeUnknown;
      });
    }
  }

  Future<void> _confirm() async {
    if (_confirming || _accountChanged) return;
    if (!_sameSession()) {
      _lock();
      return;
    }
    final token = extractVerificationToken(_token.text);
    if (token == null) {
      setState(() {
        _tokenProblem = context.l10n.emailVerifyTokenMalformed;
        _confirmFailure = null;
      });
      return;
    }
    // The code is a one-time credential: it does not stay in the field while
    // the request is in flight, and it is never shown again afterwards.
    _token.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _confirming = true;
      _tokenProblem = null;
      _confirmFailure = null;
      _confirmed = false;
    });
    try {
      final result = await widget.repository.verifyEmailToken(token: token);
      if (!mounted) return;
      setState(() {
        _confirming = false;
        result.fold(
          (failure) => _confirmFailure = failure.forPresentation(),
          (_) => _confirmed = true,
        );
      });
      if (_confirmed) await _readStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _confirmFailure = _outcomeUnknown;
      });
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _sending || _confirming;
    final enabled = !busy && !_accountChanged;
    return BlocListener<AppUserCubit, AppUserState>(
      listener: (context, state) {
        if (!_accountChanged && !_sameSession(state)) _lock();
      },
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.emailVerifyTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_accountChanged) ...[
                          _Notice(
                            text: localizedFailure(l10n, _sessionChanged),
                            isError: true,
                          ),
                          const SizedBox(height: 16),
                        ],
                        ..._statusSection(context, l10n),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: enabled && _canSend ? _send : null,
                          child: Text(
                            _sending
                                ? l10n.emailVerifySending
                                : l10n.emailVerifySend,
                          ),
                        ),
                        if (_request != null) ...[
                          const SizedBox(height: 12),
                          _Notice(
                            text:
                                _request ==
                                    EmailVerificationRequest.alreadyVerified
                                ? l10n.emailVerifyAlreadyVerified
                                : l10n.emailVerifySent,
                          ),
                        ],
                        if (_sendFailure != null) ...[
                          const SizedBox(height: 12),
                          _Notice(
                            text: localizedFailure(l10n, _sendFailure!),
                            isError: true,
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          l10n.emailVerifyPasteTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(l10n.emailVerifyPasteHint),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _token,
                          enabled: enabled && _status?.isVerified != true,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          decoration: InputDecoration(
                            labelText: l10n.emailVerifyTokenLabel,
                            errorText: _tokenProblem,
                          ),
                          onChanged: (_) {
                            if (_tokenProblem != null) {
                              setState(() => _tokenProblem = null);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: enabled && _status?.isVerified != true
                              ? _confirm
                              : null,
                          child: Text(
                            _confirming
                                ? l10n.emailVerifyTokenConfirming
                                : l10n.emailVerifyTokenConfirm,
                          ),
                        ),
                        if (_confirmed) ...[
                          const SizedBox(height: 12),
                          _Notice(text: l10n.emailVerifyTokenDone),
                        ],
                        if (_confirmFailure != null) ...[
                          const SizedBox(height: 12),
                          _Notice(
                            text: localizedFailure(l10n, _confirmFailure!),
                            isError: true,
                          ),
                        ],
                      ],
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

  /// The server never sends a link for an address that is already verified, and
  /// there is nothing to verify without an address on file.
  bool get _canSend =>
      _status != null && !_status!.isVerified && _status!.email.isNotEmpty;

  List<Widget> _statusSection(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final status = _status;
    if (_loadingStatus) {
      return [
        Semantics(liveRegion: true, child: Text(l10n.emailVerifyRefreshing)),
      ];
    }
    if (_statusFailure != null) {
      return [
        _Notice(text: localizedFailure(l10n, _statusFailure!), isError: true),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _accountChanged ? null : _readStatus,
            child: Text(l10n.emailVerifyRefresh),
          ),
        ),
      ];
    }
    if (status == null) return const [];
    return [
      if (status.email.isNotEmpty) ...[
        Text(status.email, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
      ],
      if (status.verifiedAt != null)
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.emailVerifyVerifiedOn(
              formatDate(Localizations.localeOf(context), status.verifiedAt!),
            ),
          ),
        )
      else
        Semantics(liveRegion: true, child: Text(l10n.emailVerifyUnverified)),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: _accountChanged || _loadingStatus ? null : _readStatus,
          child: Text(l10n.emailVerifyRefresh),
        ),
      ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(
          color: isError ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    );
  }
}

const _sessionChanged = Failure(
  '登录账户已变更；本次操作已作废，请重新打开本页',
  kind: FailureKind.auth,
  code: 'auth.sessionChanged',
);
const _outcomeUnknown = Failure(
  '无法确认结果：请求可能已经送达。请先检查邮箱或刷新状态，不要连续重试。',
  kind: FailureKind.unknown,
  code: 'account.verificationOutcomeUnknown',
);
const _statusUnavailable = Failure(
  '暂时无法读取邮箱状态，请稍后重试',
  kind: FailureKind.server,
  code: 'account.emailStatusUnavailable',
);
