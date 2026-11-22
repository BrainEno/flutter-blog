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

class _UnreadSummary extends StatelessWidget {
  const _UnreadSummary({required this.count, required this.onMarkAll});

  final int count;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    // One line: the count, and the action that clears it at the far end.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        NoWaveSpacing.small,
        NoWaveSpacing.page,
        NoWaveSpacing.small,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: NoWaveSpacing.medium,
        children: [
          Text(
            context.l10n.notificationsLoadedUnreadCount(count),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          NoWaveLinkButton(
            icon: Icons.done_all,
            label: context.l10n.notificationsMarkAllRead,
            onPressed: onMarkAll,
          ),
        ],
      ),
    );
  }
}

class _NotificationPaginationFooter extends StatelessWidget {
  const _NotificationPaginationFooter({
    required this.state,
    this.addressNote = false,
  });

  final NotificationInboxLoaded state;

  /// Whether to say, once, that an article a notification points at may
  /// have gone. Said under every linked row it was a third of the list.
  final bool addressNote;

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
      child: Center(
        child: addressNote
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  content,
                  const SizedBox(height: NoWaveSpacing.small),
                  Text(
                    l10n.notificationsAddressMayChange,
                    textAlign: TextAlign.center,
                    style: textStyle?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : content,
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.marking,
    required this.onMarkRead,
    this.onOpenConversation,
    this.onOpenTarget,
  });

  final AppNotification item;
  final bool marking;
  final VoidCallback onMarkRead;

  /// Opens the safe conversation target or, if absent, the message list.
  final VoidCallback? onOpenConversation;
  final VoidCallback? onOpenTarget;

  IconData get _icon => switch (item.kind) {
    AppNotificationKind.articleDeleted => Icons.delete_outline,
    AppNotificationKind.messageReceived => Icons.mail_outline,
    AppNotificationKind.articleCommented => Icons.chat_bubble_outline,
    AppNotificationKind.commentReplied => Icons.reply,
    AppNotificationKind.articleLiked => Icons.favorite_border,
    AppNotificationKind.userFollowed => Icons.person_outline,
    AppNotificationKind.unknown => Icons.notifications_none,
  };

  /// The sentence this row states. Only shapes the app understands are named;
  /// anything else says that a notification exists, without inventing details.
  String _describe(BuildContext context) => switch (item.kind) {
    AppNotificationKind.articleDeleted => _deletionSentence(context),
    AppNotificationKind.messageReceived =>
      context.l10n.notificationMessageReceived,
    AppNotificationKind.articleCommented => context.l10n.notificationCommented,
    AppNotificationKind.commentReplied => context.l10n.notificationReply,
    AppNotificationKind.articleLiked => context.l10n.notificationLiked,
    AppNotificationKind.userFollowed => context.l10n.notificationFollowed,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final icon = Icon(
      _icon,
      size: NoWaveIconSize.action,
      color: item.isRead ? scheme.onSurfaceVariant : scheme.onSurface,
    );
    // Unread is said in type and one mark, not a tinted band: the sentence
    // is set heavier, and an 8pt ink square - the same square that ends an
    // article - stands at the row's end until it is read. The band ran past
    // the gutter and all but vanished on the dark paper.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        NoWaveSpacing.medium,
        NoWaveSpacing.page,
        NoWaveSpacing.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isRead)
            icon
          else
            Semantics(
              label: context.l10n.notificationsUnreadBadge,
              child: icon,
            ),
          const SizedBox(width: NoWaveSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _describe(context),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: item.isRead
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!item.isRead) ...[
                      const SizedBox(width: NoWaveSpacing.small),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: NoWaveSpacing.small,
                        ),
                        child: ExcludeSemantics(
                          child: SizedBox.square(
                            dimension: NoWaveSizes.endMark,
                            child: ColoredBox(color: scheme.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: NoWaveSpacing.xs),
                Text(formatRecent(locale, item.createdAt), style: note),
                if (onOpenTarget != null && item.articleSourceLocale != null)
                  Text(switch (item.articleSourceLocale!) {
                    NotificationArticleLocale.english =>
                      context.l10n.notificationsSourceEnglish,
                    NotificationArticleLocale.simplifiedChinese =>
                      context.l10n.notificationsSourceSimplifiedChinese,
                    NotificationArticleLocale.traditionalChinese =>
                      context.l10n.notificationsSourceTraditionalChinese,
                  }, style: note),
                if (onOpenConversation != null &&
                    item.conversationTarget == null)
                  Text(
                    context.l10n.notificationsConversationUnavailable,
                    style: note,
                  ),
                if (onOpenTarget != null ||
                    onOpenConversation != null ||
                    !item.isRead)
                  // On the sentence's edge, a step apart: a text button's
                  // own inset used to start them inside the column.
                  Wrap(
                    spacing: NoWaveSpacing.large,
                    children: [
                      if (onOpenTarget != null)
                        NoWaveLinkButton(
                          forward: true,
                          onPressed: onOpenTarget,
                          label: item.articleTarget != null
                              ? context.l10n.notificationsOpenArticleAddress
                              : context.l10n.notificationsOpenFollower,
                        ),
                      if (onOpenConversation != null)
                        NoWaveLinkButton(
                          forward: true,
                          onPressed: onOpenConversation,
                          label: item.conversationTarget == null
                              ? context.l10n.notificationsOpenMessages
                              : context.l10n.notificationsOpenConversation,
                        ),
                      if (!item.isRead)
                        NoWaveLinkButton(
                          onPressed: marking ? null : onMarkRead,
                          label: context.l10n.notificationsMarkRead,
                        ),
                    ],
                  ),
              ],
            ),
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
