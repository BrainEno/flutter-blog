import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/account_session.dart';
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
  StreamSubscription<AppUserState>? _userSubscription;

  List<AccountSession> _sessions = const [];
  Failure? _failure;
  bool _loading = false;
  bool _invalidated = false;
  int _loadVersion = 0;

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
    _userSubscription = _userCubit.stream.listen((state) {
      final fence = _fence;
      // Inspect the emitted state too: B followed immediately by A must not
      // keep an A page alive just because the stream listener ran later.
      if (fence == null ||
          state is! AppUserLoggedIn ||
          state.user.id != fence.userId ||
          !_matchesFence) {
        _invalidate();
      }
    });
    unawaited(_reload());
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

  @override
  void dispose() {
    _loadVersion++;
    _sessions = const [];
    unawaited(_identitySubscription?.cancel());
    unawaited(_userSubscription?.cancel());
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
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: BlocBuilder<AppUserCubit, AppUserState>(
        builder: (context, _) {
          // Also check on every build, in case the app-user state changes
          // before its asynchronous listener has delivered the event.
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
                      const SizedBox(height: 16),
                      if (sessions.isEmpty)
                        NoWaveStatus(message: l10n.accountSessionsEmpty)
                      else
                        for (final session in sessions)
                          _SessionCard(session: session),
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

  Widget _status(BuildContext context, String message, {VoidCallback? retry}) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: NoWaveStatus(
            message: message,
            actionLabel: retry == null ? null : context.l10n.actionRetry,
            onAction: retry,
          ),
        ),
      );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final AccountSession session;

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
          ],
        ),
      ),
    );
  }
}
