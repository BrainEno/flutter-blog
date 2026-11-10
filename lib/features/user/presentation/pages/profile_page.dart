import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/theme_toggle_button.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/common/widgets/language_menu_button.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/messages/presentation/bloc/message_unread_badge_cubit.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_badge_cubit.dart';
import 'package:belog/features/user/domain/usecases/export_user_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// The signed-in account's own page: identity, the way into every account
/// screen, and badges for unread notifications and private messages.
///
/// The badges are page-scoped state: they read when the page opens, when the
/// account changes, and when their inbox is closed. The message count is
/// limited to the newest 50 conversations because the API has no global count
/// endpoint or list cursor. Neither badge polls; this client has no push
/// channel, so polling would spend requests to stay stale.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.badgeCubit, this.messageBadgeCubit});

  /// Injected by tests; production creates page-scoped instances.
  final NotificationBadgeCubit? badgeCubit;
  final MessageUnreadBadgeCubit? messageBadgeCubit;

  @override
  Widget build(BuildContext context) {
    final messages = messageBadgeCubit;
    final Widget profileView = messages == null
        ? BlocProvider<MessageUnreadBadgeCubit>(
            create: (_) => GetIt.instance<MessageUnreadBadgeCubit>(),
            child: const _ProfileView(),
          )
        : BlocProvider<MessageUnreadBadgeCubit>.value(
            value: messages,
            child: const _ProfileView(),
          );

    final notifications = badgeCubit;
    if (notifications != null) {
      return BlocProvider<NotificationBadgeCubit>.value(
        value: notifications,
        child: profileView,
      );
    }
    return BlocProvider<NotificationBadgeCubit>(
      create: (_) => GetIt.instance<NotificationBadgeCubit>(),
      child: profileView,
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  /// Re-reads the notification badge after returning from its inbox.
  Future<void> _openInbox(BuildContext context) async {
    final badge = context.read<NotificationBadgeCubit>();
    await context.push('/profile/notifications');
    if (!context.mounted) return;
    unawaited(badge.refresh());
  }

  /// Re-reads unread totals after messages were opened or marked read.
  Future<void> _openMessages(BuildContext context) async {
    final badge = context.read<MessageUnreadBadgeCubit>();
    await context.push('/profile/messages');
    if (!context.mounted) return;
    unawaited(badge.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.profileTitle),
        actions: const [
          ThemeToggleButton(),
          LanguageMenuButton(),
          SizedBox(width: NoWaveSpacing.medium),
        ],
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthLogoutFailure) {
            showSnackBar(context, localizedFailure(l10n, state.failure));
          }
        },
        child: BlocBuilder<AppUserCubit, AppUserState>(
          builder: (context, state) {
            if (state is! AppUserLoggedIn) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.notSignedIn),
                    const SizedBox(height: NoWaveSpacing.medium),
                    NoWaveButton(
                      label: l10n.signIn,
                      onPressed: () => context.push('/login'),
                    ),
                  ],
                ),
              );
            }
            final user = state.user;
            final name = authorDisplayName(l10n, user.name);
            // A single scrollable keeps the header and every action available
            // at large system text sizes.
            return ListView(
              padding: const EdgeInsets.all(NoWaveSpacing.page),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NoWaveAvatar(name: name, imageUrl: user.avatarUrl),
                            const SizedBox(width: NoWaveSpacing.medium),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      name,
                                      style: NoWaveTypography.title(
                                        context,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                  if (user.website.trim().isNotEmpty) ...[
                                    const SizedBox(height: NoWaveSpacing.small),
                                    Text(user.website.trim()),
                                  ],
                                  TextButton(
                                    onPressed: () => context.push(
                                      '/profile/author/${Uri.encodeComponent(user.id)}',
                                    ),
                                    child: Text(l10n.viewMyAuthorProfile),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NoWaveSpacing.section),
                        NoWaveActionRow(
                          icon: Icons.edit_outlined,
                          label: l10n.menuEditProfile,
                          onTap: () => context.push('/profile/edit'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.lock_outline,
                          label: l10n.menuChangePassword,
                          onTap: () => context.push('/profile/change-password'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.alternate_email,
                          label: l10n.accountEmailTitle,
                          description: user.email.isEmpty ? null : user.email,
                          onTap: () => context.push('/profile/change-email'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.mark_email_unread_outlined,
                          label: l10n.emailVerifyTitle,
                          onTap: () =>
                              context.push('/profile/email-verification'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.article_outlined,
                          label: l10n.menuMyArticles,
                          onTap: () => context.push('/profile/my-articles'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.history,
                          label: l10n.menuReadingHistory,
                          onTap: () => context.push('/profile/history'),
                        ),
                        BlocBuilder<NotificationBadgeCubit, int>(
                          builder: (context, unread) => NoWaveActionRow(
                            icon: Icons.notifications_none,
                            label: l10n.notificationsTitle,
                            description: l10n.notificationsMenuHint,
                            onTap: () => _openInbox(context),
                            trailing: unread > 0
                                ? _UnreadBadge(
                                    count: unread,
                                    semanticLabel: l10n.notificationsUnreadCount(
                                      unread,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        BlocBuilder<MessageUnreadBadgeCubit, int>(
                          builder: (context, unread) => NoWaveActionRow(
                            icon: Icons.mail_outline,
                            label: l10n.messagesTitle,
                            description: l10n.messagesMenuHint,
                            onTap: () => _openMessages(context),
                            trailing: unread > 0
                                ? _UnreadBadge(
                                    count: unread,
                                    semanticLabel:
                                        l10n.messagesUnreadRecentCount(unread),
                                  )
                                : null,
                          ),
                        ),
                        NoWaveActionRow(
                          icon: Icons.cloud_upload_outlined,
                          label: l10n.publishQueueTitle,
                          description: l10n.publishQueueMenuHint,
                          onTap: () => context.push('/profile/publish-queue'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.devices_outlined,
                          label: l10n.accountSessionsTitle,
                          onTap: () => context.push('/profile/sessions'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.info_outline,
                          label: l10n.menuAbout,
                          onTap: () => context.push('/profile/about'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.file_download_outlined,
                          label: l10n.exportMyData,
                          description: l10n.exportMyDataHint,
                          onTap: () => _exportData(context, user),
                        ),
                        NoWaveActionRow(
                          icon: Icons.logout,
                          label: l10n.logout,
                          onTap: () =>
                              context.read<AuthBloc>().add(AuthLogout()),
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Runs the export behind a non-dismissible progress dialog so a second
  /// tap cannot queue another network request or system share sheet.
  Future<void> _exportData(BuildContext context, User user) async {
    final exporter = GetIt.instance<ExportUserData>();
    final l10n = context.l10n;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: ColoredBox(
            color: Theme.of(dialogContext).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(NoWaveSpacing.large),
              child: NoWaveLoadingLabel(semanticLabel: l10n.loading),
            ),
          ),
        ),
      ),
    );
    Either<Failure, void> result;
    try {
      result = await exporter.exportAndShare(
        user: user,
        shareTitle: l10n.exportShareTitle,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'exporting user data failed',
        error: e,
        stackTrace: stackTrace,
      );
      result = left(Failure('导出失败，请重试', code: 'export.failed'));
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    result.fold(
      (failure) => showSnackBar(context, localizedFailure(l10n, failure)),
      (_) => showSnackBar(context, l10n.exportDone),
    );
  }
}

/// The unread count as a pill. [semanticLabel] gives screen readers its
/// meaning; the visible number is capped so a long count cannot stretch the
/// row at large text sizes.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.semanticLabel});

  final int count;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 26),
        padding: const EdgeInsets.symmetric(
          horizontal: NoWaveSpacing.small,
          vertical: 3, // design-token-ok: optical centring of the badge digit
        ),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
