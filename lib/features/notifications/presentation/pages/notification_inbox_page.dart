import 'dart:async';

import 'package:belog/core/design/components/no_wave_link_button.dart';
import 'package:belog/core/design/components/no_wave_refresh.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';

part 'notification_inbox_widgets.dart';

/// The signed-in account's notification inbox.
///
/// The server has no push channel and this app does not poll: the newest page is
/// read when the page opens, on user refresh, and when the session changes;
/// older pages are fetched only when requested. The only write is marking read -
/// one row or all of them.
class NotificationInboxPage extends StatelessWidget {
  const NotificationInboxPage({super.key, this.cubit});

  /// Injected by tests; production reads the page-scoped instance.
  final NotificationInboxCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final injected = cubit;
    if (injected != null) {
      return BlocProvider<NotificationInboxCubit>.value(
        value: injected,
        child: const _NotificationInboxView(),
      );
    }
    return BlocProvider<NotificationInboxCubit>(
      create: (_) => GetIt.instance<NotificationInboxCubit>(),
      child: const _NotificationInboxView(),
    );
  }
}

class _NotificationInboxView extends StatelessWidget {
  const _NotificationInboxView();

  bool _sameSession(
    NotificationInboxCubit inbox,
    String? userId,
    int generation,
  ) =>
      !inbox.isClosed &&
      userId != null &&
      inbox.identity.activeUserId == userId &&
      inbox.identity.sessionGeneration == generation &&
      (inbox.identity.accessToken?.isNotEmpty ?? false);

  String _markFailureText(BuildContext context, Failure failure) {
    // A write may have reached the server even when its response is lost,
    // malformed, or a server error. Avoid presenting that as a definite undo.
    const uncertainCodes = {
      'auth.sessionChanged',
      'client.parse',
      'server.parse',
      'server.error',
      'server.SERVICE_UNAVAILABLE',
    };
    if (failure.kind == FailureKind.network ||
        failure.kind == FailureKind.timeout ||
        failure.kind == FailureKind.unknown ||
        uncertainCodes.contains(failure.code)) {
      return context.l10n.notificationsReadOutcomeUnknown;
    }
    return localizedFailure(context.l10n, failure);
  }

  Future<void> _markRead(
    BuildContext context,
    NotificationInboxLoaded expected,
    String id,
    String? userId,
    int generation,
  ) async {
    final inbox = context.read<NotificationInboxCubit>();
    if (!_sameSession(inbox, userId, generation) ||
        !identical(inbox.state, expected)) {
      return;
    }
    final failure = await inbox.markRead(id);
    if (!context.mounted || !_sameSession(inbox, userId, generation)) return;
    final message = failure == null
        ? context.l10n.notificationsMarkedRead
        : _markFailureText(context, failure);
    showSnackBar(context, message);
  }

  Future<void> _markAllRead(
    BuildContext context,
    NotificationInboxLoaded expected,
    String? userId,
    int generation,
  ) async {
    final inbox = context.read<NotificationInboxCubit>();
    if (!_sameSession(inbox, userId, generation) ||
        !identical(inbox.state, expected)) {
      return;
    }
    final failure = await inbox.markAllRead();
    if (!context.mounted || !_sameSession(inbox, userId, generation)) return;
    if (failure != null) {
      showSnackBar(context, _markFailureText(context, failure));
      return;
    }
    showSnackBar(context, context.l10n.notificationsAllRead);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.notificationsTitle),
        actions: [
          BlocBuilder<NotificationInboxCubit, NotificationInboxState>(
            builder: (context, state) {
              final inbox = context.read<NotificationInboxCubit>();
              final userId = inbox.identity.activeUserId;
              final generation = inbox.identity.sessionGeneration;
              final canRefresh =
                  state is NotificationInboxLoaded &&
                  !state.isRefreshing &&
                  !state.markingAll &&
                  state.markingId == null;
              return IconButton(
                tooltip: context.l10n.notificationsRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: !canRefresh
                    ? null
                    : () {
                        if (!context.mounted ||
                            !_sameSession(inbox, userId, generation) ||
                            !identical(inbox.state, state)) {
                          return;
                        }
                        unawaited(inbox.load(showLoading: false));
                      },
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationInboxCubit, NotificationInboxState>(
        builder: (context, state) {
          if (state is NotificationInboxLoading) {
            return NoWaveSkeletonList(
              thumbnails: false,
              semanticLabel: context.l10n.loading,
            );
          }
          if (state is NotificationInboxSignedOut) {
            return _EmptyInbox(
              title: context.l10n.notificationsSignInTitle,
              body: context.l10n.notificationsEmptyBody,
              actionLabel: context.l10n.notificationsSignIn,
              onAction: () => context.push(RoutePaths.login),
            );
          }
          if (state is NotificationInboxFailure) {
            return _InboxError(failure: state.failure);
          }
          final loaded = state as NotificationInboxLoaded;
          final showSummary = loaded.unreadCount > 0;
          final showPaginationFooter =
              loaded.items.isNotEmpty && !loaded.isRefreshing;
          final extra = (showSummary ? 1 : 0) + (showPaginationFooter ? 1 : 0);
          return NoWaveRefresh(
            onRefresh: () =>
                context.read<NotificationInboxCubit>().load(showLoading: false),
            child: loaded.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: NoWaveSizes.emptyStateOffset),
                      _EmptyInbox(
                        title: context.l10n.notificationsEmptyTitle,
                        body: context.l10n.notificationsEmptyBody,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      vertical: NoWaveSpacing.small,
                    ),
                    itemCount: loaded.items.length + extra,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: NoWaveSpacing.page,
                      endIndent: NoWaveSpacing.page,
                    ),
                    itemBuilder: (context, index) {
                      final row = index - (showSummary ? 1 : 0);
                      if (row < 0) {
                        final identity = context
                            .read<NotificationInboxCubit>()
                            .identity;
                        final userId = identity.activeUserId;
                        final generation = identity.sessionGeneration;
                        return _UnreadSummary(
                          count: loaded.unreadCount,
                          onMarkAll:
                              loaded.markingAll ||
                                  loaded.markingId != null ||
                                  loaded.isLoadingMore ||
                                  loaded.isRefreshing
                              ? null
                              : () => _markAllRead(
                                  context,
                                  loaded,
                                  userId,
                                  generation,
                                ),
                        );
                      }
                      if (row >= loaded.items.length) {
                        return _NotificationPaginationFooter(
                          state: loaded,
                          addressNote: loaded.items.any(
                            (item) => item.articleTarget != null,
                          ),
                        );
                      }
                      final item = loaded.items[row];
                      final conversationId = item.conversationTarget;
                      final articleTarget = item.articleTarget;
                      final followerTarget = item.followerTarget;
                      final inbox = context.read<NotificationInboxCubit>();
                      final userId = inbox.identity.activeUserId;
                      final generation = inbox.identity.sessionGeneration;
                      void open(String route) {
                        final state = inbox.state;
                        if (!context.mounted ||
                            inbox.isClosed ||
                            userId == null ||
                            inbox.identity.activeUserId != userId ||
                            inbox.identity.sessionGeneration != generation ||
                            (inbox.identity.accessToken?.isEmpty ?? true) ||
                            state is! NotificationInboxLoaded ||
                            !state.items.any((row) => identical(row, item))) {
                          return;
                        }
                        context.push(route);
                      }

                      return _NotificationRow(
                        item: item,
                        marking:
                            loaded.markingId != null ||
                            loaded.markingAll ||
                            loaded.isRefreshing,
                        onMarkRead: () => _markRead(
                          context,
                          loaded,
                          item.id,
                          userId,
                          generation,
                        ),
                        onOpenTarget: articleTarget != null
                            ? () => open(RoutePaths.profileView(articleTarget))
                            : followerTarget != null
                            ? () =>
                                  open(RoutePaths.profileAuthor(followerTarget))
                            : null,
                        onOpenConversation:
                            item.kind != AppNotificationKind.messageReceived
                            ? null
                            : () => open(
                                conversationId == null
                                    ? RoutePaths.messages
                                    : RoutePaths.messageThread(conversationId),
                              ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
