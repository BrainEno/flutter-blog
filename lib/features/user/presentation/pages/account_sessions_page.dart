import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
import 'package:belog/features/user/domain/entities/session_revoke_outcome.dart';
import 'package:belog/features/user/domain/repositories/account_session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

/// Read-only, online-only view of the initiating sign-in's session list.
/// Reopening the page is required after *any* account/session replacement,
/// including signing in again as the same user.
class AccountSessionsPage extends StatefulWidget {
  const AccountSessionsPage({super.key, this.repository, this.identity});

  /// Optional injection points for tests. Production uses the same session
  /// manager that authenticates the API client.
  final AccountSessionRepository? repository;
  final NowaveSessionIdentity? identity;

  @override
  State<AccountSessionsPage> createState() => _AccountSessionsPageState();
}

class _AccountSessionsPageState extends State<AccountSessionsPage> {
  late final AccountSessionRepository _repository;
  late final NowaveSessionIdentity _identity;
  late final AppUserCubit _userCubit;
  late final NowaveSessionFence? _fence;
  StreamSubscription<void>? _identitySubscription;
  bool _listeningToUser = false;

  List<AccountSession> _sessions = const [];
  Failure? _failure;
  bool _loading = false;
  bool _invalidated = false;
  int _loadVersion = 0;

  /// The row (or `null` for "every other session") currently being ended, plus
  /// the one sentence this page is allowed to claim afterwards.
  String? _revokingId;
  bool _revokingOthers = false;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? GetIt.instance<AccountSessionRepository>();
    _identity = widget.identity ?? GetIt.instance<NowaveSessionManager>();
    _userCubit = context.read<AppUserCubit>();
    final state = _userCubit.state;
    final userId = state is AppUserLoggedIn ? state.user.id : null;
    if (userId == null ||
        userId.isEmpty ||
        _identity.activeUserId != userId ||
        (_identity.accessToken?.isEmpty ?? true)) {
      _fence = null;
      _invalidated = true;
      return;
    }
    _fence = NowaveSessionFence(
      userId: userId,
      generation: _identity.sessionGeneration,
    );
    // The identity stream is synchronous. Drop the old list as soon as the
    // session is replaced, without waiting for the app-user sync or HTTP.
    _identitySubscription = _identity.identityChanges.listen((_) {
      if (!_matchesFence) _invalidate();
    });
    _userCubit.identityRevision.addListener(_onUserRevision);
    _listeningToUser = true;
    unawaited(_reload());
  }

  void _onUserRevision() {
    if (!_matchesFence) _invalidate();
  }

  bool get _matchesFence {
    final fence = _fence;
    final state = _userCubit.state;
    return !_invalidated &&
        fence != null &&
        state is AppUserLoggedIn &&
        state.user.id == fence.userId &&
        _identity.activeUserId == fence.userId &&
        _identity.sessionGeneration == fence.generation &&
        !(_identity.accessToken?.isEmpty ?? true);
  }

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _loadVersion++;
    setState(() {
      _invalidated = true;
      _sessions = const [];
      _failure = null;
      _loading = false;
      _revokingId = null;
      _revokingOthers = false;
      _notice = null;
    });
  }

  Future<void> _reload() async {
    if (_loading) return;
    if (!_matchesFence) {
      _invalidate();
      return;
    }
    final version = ++_loadVersion;
    final fence = _fence!;
    setState(() {
      // Do not present an old result as current while retrying or offline.
      _sessions = const [];
      _failure = null;
      _loading = true;
    });
    try {
      final result = await _repository.listSessions(fence);
      if (!mounted || version != _loadVersion || !_matchesFence) return;
      setState(() {
        _loading = false;
        result.fold(
          (failure) => _failure = failure.forPresentation(),
          (sessions) => _sessions = List.unmodifiable(sessions),
        );
      });
    } catch (_) {
      // The repository normally returns a typed error. Never render or log
      // an unexpected exception, which could contain remote data.
      if (!mounted || version != _loadVersion || !_matchesFence) return;
      setState(() {
        _loading = false;
        _failure = const Failure('服务器暂时不可用，请稍后重试', code: 'server.error');
      });
    }
  }

  /// Asks for confirmation, then ends one session.
  ///
  /// Ending a session is not a credential change and not undoable, so it gets a
  /// dialog rather than a swipe: the row that disappears is a device someone
  /// will have to sign in on again.
  Future<void> _confirmEndOne(AccountSession session) async {
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.accountSessionsEndThisTitle,
      message: l10n.accountSessionsEndThisBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.accountSessionsEndConfirm,
    );
    if (!confirmed || !mounted) return;
    await _endOne(session);
  }

  Future<void> _confirmEndOthers() async {
    final l10n = context.l10n;
    final currentUnknown =
        _sessions.isNotEmpty && !_sessions.any((session) => session.current);
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.accountSessionsEndOthersTitle,
      message: currentUnknown
          ? l10n.accountSessionsEndOthersUnknownCurrent
          : l10n.accountSessionsEndOthersBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.accountSessionsEndConfirm,
    );
    if (!confirmed || !mounted) return;
    await _endOthers();
  }

  Future<void> _endOne(AccountSession session) async {
    final fence = _fence;
    if (_busy || fence == null || !_matchesFence) {
      _invalidate();
      return;
    }
    setState(() {
      _revokingId = session.id;
      _notice = null;
      _noticeIsError = false;
    });
    try {
      final result = await _repository.revokeSession(fence, session.id);
      if (!mounted) return;
      setState(() {
        _revokingId = null;
        result.fold(
          (failure) => _notice = localizedFailure(context.l10n, failure),
          (outcome) => _notice = outcome == SessionRevokeOutcome.ended
              ? context.l10n.accountSessionsEndedOne
              : context.l10n.accountSessionsAlreadyEnded,
        );
        _noticeIsError = result.isLeft();
      });
      // The list is the server's claim; re-read it instead of removing a row
      // locally and hoping that matches.
      await _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _revokingId = null;
        _notice = context.l10n.accountSessionsEndUnknown;
        _noticeIsError = true;
      });
    }
  }

  Future<void> _endOthers() async {
    final fence = _fence;
    if (_busy || fence == null || !_matchesFence) {
      _invalidate();
      return;
    }
    setState(() {
      _revokingOthers = true;
      _notice = null;
      _noticeIsError = false;
    });
    try {
      final result = await _repository.revokeOtherSessions(fence);
      if (!mounted) return;
      setState(() {
        _revokingOthers = false;
        result.fold(
          (failure) => _notice = localizedFailure(context.l10n, failure),
          (count) => _notice = count == 0
              ? context.l10n.accountSessionsEndedNone
              : context.l10n.accountSessionsEndedOthers(count),
        );
        _noticeIsError = result.isLeft();
      });
      await _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _revokingOthers = false;
        _notice = context.l10n.accountSessionsEndUnknown;
        _noticeIsError = true;
      });
    }
  }

  bool get _busy => _revokingId != null || _revokingOthers;

  @override
  void dispose() {
    _loadVersion++;
    _sessions = const [];
    unawaited(_identitySubscription?.cancel());
    if (_listeningToUser) {
      _userCubit.identityRevision.removeListener(_onUserRevision);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountSessionsTitle),
        actions: [
          if (_matchesFence)
            IconButton(
              tooltip: l10n.accountSessionsRefresh,
              onPressed: _loading || _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: BlocBuilder<AppUserCubit, AppUserState>(
        builder: (context, _) {
          // Double-check the current identity on every build in addition
          // to the synchronous invalidation signals.
          if (!_matchesFence) {
            return _status(context, l10n.accountSessionsChanged);
          }
          if (_loading) {
            return Center(
              child: CircularProgressIndicator(semanticsLabel: l10n.loading),
            );
          }
          final failure = _failure;
          if (failure != null) {
            return _status(
              context,
              localizedFailure(l10n, failure),
              retry: _reload,
            );
          }
          final sessions = _sessions;
          final currentUnknown =
              sessions.isNotEmpty &&
              !sessions.any((session) => session.current);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.accountSessionsDescription),
                      if (currentUnknown) ...[
                        const SizedBox(height: 12),
                        Text(l10n.accountSessionsCurrentUnknown),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 12),
                        _NoticeMessage(text: _notice!, isError: _noticeIsError),
                      ],
                      const SizedBox(height: 16),
                      if (sessions.isEmpty)
                        NoWaveStatus(message: l10n.accountSessionsEmpty)
                      else ...[
                        // The lost-phone answer: everything else goes, this
                        // device stays. Offered before the rows because it is
                        // the reason most people open this page.
                        OutlinedButton(
                          onPressed: _busy ? null : _confirmEndOthers,
                          child: Text(
                            _revokingOthers
                                ? l10n.accountSessionsEnding
                                : l10n.accountSessionsEndOthers,
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final session in sessions)
                          _SessionCard(
                            session: session,
                            busy: _revokingId == session.id,
                            onEnd: session.current || _busy
                                ? null
                                : () => _confirmEndOne(session),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _status(BuildContext context, String message, {VoidCallback? retry}) {
    final notice = _notice;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // What already happened stays visible even when the follow-up read
            // of the list failed; otherwise an ended session would look like a
            // failed one.
            if (notice != null) ...[
              _NoticeMessage(text: notice, isError: _noticeIsError),
              const SizedBox(height: 16),
            ],
            NoWaveStatus(
              message: message,
              actionLabel: retry == null ? null : context.l10n.actionRetry,
              onAction: retry,
            ),
          ],
        ),
      ),
    );
  }
}

/// One sentence about what the last revocation did (or failed to do).
class _NoticeMessage extends StatelessWidget {
  const _NoticeMessage({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: TextStyle(
        color: isError ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.busy,
    required this.onEnd,
  });

  final AccountSession session;

  /// True while *this* row is being ended; the label changes so the row itself
  /// says what is happening.
  final bool busy;

  /// Null while any revocation is in flight, which disables the button.
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    String time(DateTime value) =>
        DateFormat.yMMMd(locale.toString()).add_jms().format(value.toLocal());
    final lastRefreshed = session.lastRefreshedAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                session.current
                    ? l10n.accountSessionsCurrent
                    : l10n.accountSessionsOther,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.accountSessionsCreated(time(session.createdAt))),
            Text(
              lastRefreshed == null
                  ? l10n.accountSessionsNeverRefreshed
                  : l10n.accountSessionsRefreshed(time(lastRefreshed)),
            ),
            Text(l10n.accountSessionsExpires(time(session.expiresAt))),
            // The session in use has no button: ending it is what the sign-out
            // button does, and that needs a different confirmation.
            if (!session.current) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onEnd,
                  child: Text(
                    busy
                        ? l10n.accountSessionsEnding
                        : l10n.accountSessionsEndThis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
