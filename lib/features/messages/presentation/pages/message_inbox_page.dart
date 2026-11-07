import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// The signed-in account's private conversations.
///
/// The server has no push channel and this app does not poll: the list is read
/// when the page opens, on pull-to-refresh, and when the session changes.
///
/// [startWith] is a recipient user id, which is how "发私信" on an author page
/// arrives here. An existing conversation with that person is opened instead of
/// creating a second one: the server treats every create as a new conversation.
class MessageInboxPage extends StatelessWidget {
  const MessageInboxPage({super.key, this.cubit, this.startWith});

  /// Injected by tests; production reads the page-scoped instance.
  final MessageInboxCubit? cubit;

  final String? startWith;

  @override
  Widget build(BuildContext context) {
    final injected = cubit;
    final view = _MessageInboxView(startWith: startWith);
    if (injected != null) {
      return BlocProvider<MessageInboxCubit>.value(
        value: injected,
        child: view,
      );
    }
    return BlocProvider<MessageInboxCubit>(
      create: (_) => GetIt.instance<MessageInboxCubit>(),
      child: view,
    );
  }
}

class _MessageInboxView extends StatefulWidget {
  const _MessageInboxView({this.startWith});

  final String? startWith;

  @override
  State<_MessageInboxView> createState() => _MessageInboxViewState();
}

class _MessageInboxViewState extends State<_MessageInboxView> {
  /// The recipient an author page asked us to open a conversation with.
  MessageParticipant? _recipient;

  /// Whether the pending recipient has already been handled (opened or
  /// offered), so a rebuild does not navigate twice.
  bool _handledStart = false;

  @override
  void initState() {
    super.initState();
    final recipientId = widget.startWith;
    if (recipientId == null || recipientId.isEmpty) {
      _handledStart = true;
      return;
    }
    _loadRecipient(recipientId);
  }

  Future<void> _loadRecipient(String userId) async {
    final participant = await context
        .read<MessageInboxCubit>()
        .resolveParticipant(userId);
    if (!mounted) return;
    setState(() => _recipient = participant);
  }

  /// Opens the existing conversation with the pending recipient, or leaves the
  /// "start" card on screen when there is none yet.
  void _handlePendingStart(MessageInboxLoaded state) {
    final recipientId = widget.startWith;
    if (_handledStart || recipientId == null || recipientId.isEmpty) return;
    final existing = state.existingWith(recipientId);
    if (existing == null) {
      _handledStart = true;
      return;
    }
    _handledStart = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openThread(existing.id);
    });
  }

  Future<void> _openThread(String conversationId) async {
    await context.push(
      '/profile/messages/${Uri.encodeComponent(conversationId)}',
    );
    if (!mounted) return;
    // Reading (and marking read) inside the thread is what changes these rows.
    await context.read<MessageInboxCubit>().load(showLoading: false);
  }

  Future<void> _startConversation() async {
    final recipientId = widget.startWith;
    if (recipientId == null || recipientId.isEmpty) return;
    final result = await context.read<MessageInboxCubit>().startConversation(
      recipientId,
    );
    if (!mounted) return;
    result.fold(
      (failure) =>
          showSnackBar(context, localizedFailure(context.l10n, failure)),
      (conversationId) => _openThread(conversationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.messagesTitle), centerTitle: true),
      body: BlocBuilder<MessageInboxCubit, MessageInboxState>(
        builder: (context, state) {
          // Handled while building rather than from a listener: the first load
          // can finish before this widget subscribes, and a listener would
          // then never see it.
          if (state is MessageInboxLoaded) _handlePendingStart(state);
          if (state is MessageInboxLoading) {
            return Center(
              child: CircularProgressIndicator(semanticsLabel: l10n.loading),
            );
          }
          if (state is MessageInboxSignedOut) {
            return _InboxStatus(
              message: l10n.messagesEmptyTitle,
              actionLabel: l10n.signIn,
              onAction: () => context.push('/login'),
            );
          }
          if (state is MessageInboxFailure) {
            return _InboxStatus(
              message: localizedFailure(l10n, state.failure),
              actionLabel: l10n.actionRetry,
              onAction: () => context.read<MessageInboxCubit>().load(),
            );
          }
          final loaded = state as MessageInboxLoaded;
          final showStartCard = _showStartCard(loaded);
          return RefreshIndicator(
            onRefresh: () =>
                context.read<MessageInboxCubit>().load(showLoading: false),
            child: loaded.isEmpty && !showStartCard
                ? ListView(
                    children: [
                      const SizedBox(height: 96),
                      NoWaveStatus(message: l10n.messagesEmptyBody),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: NoWaveSpacing.small,
                    ),
                    itemCount:
                        loaded.conversations.length +
                        (showStartCard ? 1 : 0) +
                        (loaded.isCapped ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (showStartCard && index == 0) {
                        return _StartConversationCard(
                          recipient: _recipient,
                          starting:
                              loaded.startingRecipient == widget.startWith,
                          onStart: _startConversation,
                        );
                      }
                      final row = index - (showStartCard ? 1 : 0);
                      if (row >= loaded.conversations.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            NoWaveSpacing.medium,
                            12,
                            NoWaveSpacing.medium,
                            NoWaveSpacing.medium,
                          ),
                          child: Text(
                            l10n.messagesInboxCapped(
                              MessageInboxCubit.pageLimit,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }
                      final conversation = loaded.conversations[row];
                      return _ConversationRow(
                        conversation: conversation,
                        viewerId: loaded.viewerId,
                        participants: loaded.participants,
                        onTap: () => _openThread(conversation.id),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  /// True while an author page asked for a conversation that does not exist
  /// yet: the card is the only way to create it from here.
  bool _showStartCard(MessageInboxLoaded state) {
    final recipientId = widget.startWith;
    if (recipientId == null || recipientId.isEmpty) return false;
    if (state.existingWith(recipientId) != null) return false;
    return true;
  }
}

class _StartConversationCard extends StatelessWidget {
  const _StartConversationCard({
    required this.recipient,
    required this.starting,
    required this.onStart,
  });

  final MessageParticipant? recipient;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = recipient?.hasName ?? false
        ? recipient!.displayName
        : l10n.messagesUnknownParticipant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.medium,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.messagesStartTitle(name),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          NoWaveButton(
            label: starting ? l10n.messagesStarting : l10n.messagesStart,
            onPressed: starting ? null : onStart,
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.viewerId,
    required this.participants,
    required this.onTap,
  });

  final Conversation conversation;
  final String viewerId;
  final Map<String, MessageParticipant> participants;
  final VoidCallback onTap;

  String _names(BuildContext context) {
    final l10n = context.l10n;
    final others = conversation.others(viewerId);
    if (others.isEmpty) return l10n.messagesYou;
    final known = <String>[];
    var unknown = 0;
    for (final id in others) {
      final participant = participants[id];
      if (participant != null && participant.hasName) {
        known.add(participant.displayName);
      } else {
        unknown++;
      }
    }
    if (unknown > 0) known.add(l10n.messagesUnknownParticipant);
    return known.join('、');
  }

  MessageParticipant? get _firstParticipant {
    for (final id in conversation.others(viewerId)) {
      final participant = participants[id];
      if (participant != null) return participant;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _names(context);
    final participant = _firstParticipant;
    final lastEventAt = conversation.lastEventAt;
    final preview = conversation.lastMessage?.body;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.medium,
          12,
          NoWaveSpacing.medium,
          12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoWaveAvatar(
              name: name,
              imageUrl: participant?.avatarUrl ?? '',
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastEventAt != null) ...[
                        const SizedBox(width: NoWaveSpacing.small),
                        // Shares the row with the name instead of owning its
                        // width: at 2x text a localized date alone is wider
                        // than a 320px screen allows.
                        Flexible(
                          child: Text(
                            formatDate(
                              Localizations.localeOf(context),
                              lastEventAt,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: NoWaveTypography.meta(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: NoWaveSpacing.xs),
                  Text(
                    preview == null || preview.trim().isEmpty
                        ? l10n.messagesThreadEmpty
                        : preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (conversation.unreadCount > 0) ...[
              const SizedBox(width: NoWaveSpacing.small),
              _UnreadPill(count: conversation.unreadCount),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.messagesUnreadCount(count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
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

class _InboxStatus extends StatelessWidget {
  const _InboxStatus({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NoWaveSpacing.large),
        child: NoWaveStatus(
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}
