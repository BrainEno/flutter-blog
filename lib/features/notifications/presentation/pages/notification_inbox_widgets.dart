part of 'notification_inbox_page.dart';

// The inbox's pieces: the unread summary, one notification row, the
// pagination footer, and the error and empty states.

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
