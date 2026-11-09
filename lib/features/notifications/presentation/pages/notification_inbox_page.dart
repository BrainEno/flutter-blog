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

/// The signed-in account's notification inbox.
///
/// The server has no push channel and this app does not poll: the newest page is
/// read when the page opens, on pull-to-refresh, and when the session changes;
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

  Future<void> _markRead(BuildContext context, String id) async {
    final failure = await context.read<NotificationInboxCubit>().markRead(id);
    if (!context.mounted) return;
    final message = failure == null
        ? context.l10n.notificationsMarkedRead
        : localizedFailure(context.l10n, failure);
    showSnackBar(context, message);
  }

  Future<void> _markAllRead(BuildContext context) async {
    final failure = await context.read<NotificationInboxCubit>().markAllRead();
    if (!context.mounted) return;
    if (failure != null) {
      showSnackBar(context, localizedFailure(context.l10n, failure));
      return;
    }
    showSnackBar(context, context.l10n.notificationsAllRead);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.notificationsTitle),
        centerTitle: true,
        actions: [
          BlocBuilder<NotificationInboxCubit, NotificationInboxState>(
            builder: (context, state) {
              if (state is! NotificationInboxLoaded) {
                return const SizedBox.shrink();
              }
              if (state.unreadCount == 0) return const SizedBox.shrink();
              final busy =
                  state.markingAll || state.isLoadingMore || state.isRefreshing;
              return TextButton(
                onPressed: busy ? null : () => _markAllRead(context),
                child: Text(context.l10n.notificationsMarkAllRead),
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
              onAction: () => context.push('/login'),
            );
          }
          if (state is NotificationInboxFailure) {
            return _InboxError(failure: state.failure);
          }
          final loaded = state as NotificationInboxLoaded;
          final showSummary = loaded.unreadCount > 0;
          final showPaginationFooter =
              loaded.items.isNotEmpty && !loaded.isRefreshing;
          final extra =
              (showSummary ? 1 : 0) + (showPaginationFooter ? 1 : 0);
          return RefreshIndicator(
            onRefresh: () =>
                context.read<NotificationInboxCubit>().load(showLoading: false),
            child: loaded.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: NoWaveSizes.emptyStateOffset),
                      _EmptyInbox(
                        title: context.l10n.notificationsEmptyTitle,
                        body: context.l10n.notificationsEmptyBody,
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: NoWaveSpacing.small,
                    ),
                    itemCount: loaded.items.length + extra,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = index - (showSummary ? 1 : 0);
                      if (row < 0) {
                        return _UnreadSummary(count: loaded.unreadCount);
                      }
                      if (row >= loaded.items.length) {
                        return _NotificationPaginationFooter(state: loaded);
                      }
                      final item = loaded.items[row];
                      final conversationId = item.conversationId;
                      return _NotificationRow(
                        item: item,
                        marking: loaded.markingId == item.id,
                        onMarkRead: () => _markRead(context, item.id),
                        onOpenConversation: conversationId == null
                            ? null
                            : () => context.push(
                                '/profile/messages/'
                                '${Uri.encodeComponent(conversationId)}',
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

class _UnreadSummary extends StatelessWidget {
  const _UnreadSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
      ),
      child: Text(
        context.l10n.notificationsLoadedUnreadCount(count),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _NotificationPaginationFooter extends StatelessWidget {
  const _NotificationPaginationFooter({required this.state});

  final NotificationInboxLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final content = switch (state) {
      _ when state.paginationUnavailable => Text(
        l10n.notificationsCursorUnavailable,
        textAlign: TextAlign.center,
        style: textStyle,
      ),
      _ when state.isLoadingMore => NoWaveLoadingLabel(
        label: l10n.notificationsLoadingOlder,
        compact: true,
      ),
      _ when state.loadMoreFailure != null => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            localizedFailure(l10n, state.loadMoreFailure!),
            textAlign: TextAlign.center,
            style: textStyle,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          NoWaveButton(
            label: l10n.notificationsRetry,
            variant: NoWaveButtonVariant.secondary,
            onPressed: state.markingAll
                ? null
                : () => context.read<NotificationInboxCubit>().loadMore(),
          ),
        ],
      ),
      _ when state.hasMore => NoWaveButton(
        label: l10n.notificationsLoadOlder,
        variant: NoWaveButtonVariant.secondary,
        onPressed: state.markingAll
            ? null
            : () => context.read<NotificationInboxCubit>().loadMore(),
      ),
      _ => Text(
        l10n.notificationsNoOlder,
        textAlign: TextAlign.center,
        style: textStyle,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.medium,
        NoWaveSpacing.medium,
      ),
      child: Center(child: content),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.marking,
    required this.onMarkRead,
    this.onOpenConversation,
  });

  final AppNotification item;
  final bool marking;
  final VoidCallback onMarkRead;

  /// Set when this notification points at a conversation the app can open.
  final VoidCallback? onOpenConversation;

  IconData get _icon => switch (item.kind) {
    AppNotificationKind.articleDeleted => Icons.delete_outline,
    AppNotificationKind.messageReceived => Icons.mail_outline,
    AppNotificationKind.unknown => Icons.notifications_none,
  };

  /// The sentence this row states. Only shapes the app understands are named;
  /// anything else says that a notification exists, without inventing details.
  String _describe(BuildContext context) => switch (item.kind) {
    AppNotificationKind.articleDeleted => _deletionSentence(context),
    AppNotificationKind.messageReceived =>
      context.l10n.notificationMessageReceived,
    AppNotificationKind.unknown => context.l10n.notificationUnknown,
  };

  String _deletionSentence(BuildContext context) {
    final purgesAt = item.purgesAt;
    if (purgesAt == null) return context.l10n.notificationArticleDeletedNoDate;
    final date = formatDate(Localizations.localeOf(context), purgesAt);
    return context.l10n.notificationArticleDeleted(date);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Container(
      color: item.isRead
          ? null
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isRead)
            Icon(_icon, size: 20)
          else
            Semantics(
              label: context.l10n.notificationsUnreadBadge,
              child: Icon(_icon, size: 20),
            ),
          const SizedBox(width: NoWaveSpacing.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_describe(context)),
                const SizedBox(height: NoWaveSpacing.xs),
                Text(
                  formatDate(locale, item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onOpenConversation != null)
            TextButton(
              onPressed: onOpenConversation,
              child: Text(context.l10n.notificationsOpenConversation),
            ),
          if (!item.isRead)
            TextButton(
              onPressed: marking ? null : onMarkRead,
              child: Text(context.l10n.notificationsMarkRead),
            ),
        ],
      ),
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizedFailure(context.l10n, failure),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NoWaveSpacing.medium),
            NoWaveButton(
              label: context.l10n.notificationsRetry,
              variant: NoWaveButtonVariant.secondary,
              onPressed: () => context.read<NotificationInboxCubit>().load(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: NoWaveSpacing.small),
            Text(body, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: NoWaveSpacing.medium),
              NoWaveButton(
                label: actionLabel!,
                variant: NoWaveButtonVariant.secondary,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
