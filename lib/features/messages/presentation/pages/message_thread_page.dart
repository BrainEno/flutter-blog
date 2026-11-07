import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// One private conversation.
///
/// Reading is explicit in both directions: the newest page is read when the
/// page opens, older pages when the reader asks, and "mark read" is a button -
/// the server marks everything it has already received, including messages this
/// device has not loaded, which is too much to do silently.
class MessageThreadPage extends StatelessWidget {
  const MessageThreadPage({
    super.key,
    required this.conversationId,
    this.cubit,
  });

  final String conversationId;

  /// Injected by tests; production builds a page-scoped cubit.
  final MessageThreadCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final injected = cubit;
    final view = _MessageThreadView(conversationId: conversationId);
    if (injected != null) {
      return BlocProvider<MessageThreadCubit>.value(
        value: injected,
        child: view,
      );
    }
    return BlocProvider<MessageThreadCubit>(
      create: (_) =>
          GetIt.instance<MessageThreadCubitFactory>().create(conversationId),
      child: view,
    );
  }
}

class _MessageThreadView extends StatefulWidget {
  const _MessageThreadView({required this.conversationId});

  final String conversationId;

  @override
  State<_MessageThreadView> createState() => _MessageThreadViewState();
}

class _MessageThreadViewState extends State<_MessageThreadView> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// The key of the message this editor is trying to send, and the text it
  /// belongs to. Retrying the same text reuses the key so the server replays
  /// the stored message; editing the text starts a new intent.
  String? _pendingKey;
  String? _pendingKeyBody;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _keyFor(String body) {
    if (_pendingKey == null || _pendingKeyBody != body) {
      _pendingKeyBody = body;
      _pendingKey = const Uuid().v4();
    }
    return _pendingKey!;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    final cubit = context.read<MessageThreadCubit>();
    final sent = body;
    final failure = await cubit.send(body: sent, idempotencyKey: _keyFor(sent));
    if (!mounted) return;
    if (failure != null) return; // the draft stays, with its key
    _pendingKey = null;
    _pendingKeyBody = null;
    if (_composer.text.trim() == sent) _composer.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _loadOlder() async {
    final before = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    await context.read<MessageThreadCubit>().loadOlder();
    if (!mounted || !_scroll.hasClients) return;
    // Prepending grows the list above the reader; shift by the same amount so
    // the message they were reading stays under their eyes.
    final grown = _scroll.position.maxScrollExtent - before;
    if (grown > 0) _scroll.jumpTo(offset + grown);
  }

  String _title(MessageThreadState state) {
    final l10n = context.l10n;
    if (state is! MessageThreadLoaded) return l10n.messagesThreadTitle;
    final others = state.conversation.others(state.viewerId);
    final names = <String>[];
    for (final id in others) {
      final participant = state.participants[id];
      if (participant != null && participant.hasName) {
        names.add(participant.displayName);
      } else {
        names.add(l10n.messagesUnknownParticipant);
      }
    }
    return names.isEmpty ? l10n.messagesThreadTitle : names.join('、');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<MessageThreadCubit, MessageThreadState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(_title(state)), centerTitle: true),
          body: switch (state) {
            MessageThreadLoading() => Center(
              child: CircularProgressIndicator(semanticsLabel: l10n.loading),
            ),
            MessageThreadSignedOut() => _ThreadStatus(
              message: l10n.messagesEmptyTitle,
              actionLabel: l10n.signIn,
              onAction: () => context.push('/login'),
            ),
            MessageThreadMissing() => _ThreadStatus(
              message: l10n.messagesMissing,
            ),
            MessageThreadFailure(:final failure) => _ThreadStatus(
              message: localizedFailure(l10n, failure),
              actionLabel: l10n.actionRetry,
              onAction: () => context.read<MessageThreadCubit>().load(),
            ),
            MessageThreadLoaded loaded => _ThreadBody(
              state: loaded,
              composer: _composer,
              scroll: _scroll,
              onSend: _send,
              onLoadOlder: _loadOlder,
            ),
          },
        );
      },
    );
  }
}

class _ThreadBody extends StatelessWidget {
  const _ThreadBody({
    required this.state,
    required this.composer,
    required this.scroll,
    required this.onSend,
    required this.onLoadOlder,
  });

  final MessageThreadLoaded state;
  final TextEditingController composer;
  final ScrollController scroll;
  final Future<void> Function() onSend;
  final Future<void> Function() onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = state.sendFailure;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          if (state.unreadCount > 0)
            _MarkReadBanner(
              hint: l10n.messagesMarkReadHint,
              marking: state.markingRead,
              onMarkRead: () => context.read<MessageThreadCubit>().markRead(),
            ),
          if (state.markedRead)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.medium,
                NoWaveSpacing.small,
                NoWaveSpacing.medium,
                0,
              ),
              child: Text(
                l10n.messagesMarkedRead,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: state.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(NoWaveSpacing.large),
                      child: NoWaveStatus(message: l10n.messagesThreadEmpty),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NoWaveSpacing.medium,
                      vertical: NoWaveSpacing.small,
                    ),
                    itemCount: state.messages.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (state.hasMore && index == 0) {
                        return _LoadOlder(
                          loading: state.loadingOlder,
                          failure: state.olderFailure,
                          onLoadOlder: onLoadOlder,
                        );
                      }
                      final message =
                          state.messages[index - (state.hasMore ? 1 : 0)];
                      return _MessageBubble(
                        message: message,
                        mine: message.senderId == state.viewerId,
                      );
                    },
                  ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.medium,
                NoWaveSpacing.small,
                NoWaveSpacing.medium,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedFailure(l10n, failure),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Text(
                    l10n.messagesDraftKept,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(NoWaveSpacing.small),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: composer,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    enabled: !state.sending,
                    decoration: InputDecoration(
                      hintText: l10n.messagesComposerHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: NoWaveSpacing.small),
                IconButton(
                  onPressed: state.sending ? null : () => onSend(),
                  tooltip: l10n.actionSend,
                  icon: state.sending
                      ? const SizedBox.square(
                          dimension: NoWaveIconSize.inline,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkReadBanner extends StatelessWidget {
  const _MarkReadBanner({
    required this.hint,
    required this.marking,
    required this.onMarkRead,
  });

  final String hint;
  final bool marking;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: marking ? null : onMarkRead,
            child: Text(context.l10n.messagesMarkRead),
          ),
        ],
      ),
    );
  }
}

class _LoadOlder extends StatelessWidget {
  const _LoadOlder({
    required this.loading,
    required this.failure,
    required this.onLoadOlder,
  });

  final bool loading;
  final Failure? failure;
  final Future<void> Function() onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.small),
      child: Column(
        children: [
          TextButton(
            onPressed: loading ? null : () => onLoadOlder(),
            child: Text(l10n.messagesLoadOlder),
          ),
          if (failure != null)
            Text(
              localizedFailure(l10n, failure!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ConversationMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = mine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.xs),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NoWaveSpacing.small,
              vertical: NoWaveSpacing.small,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.body,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
          const SizedBox(height: 2), // design-token-ok: baseline nudge
          Text(
            formatDate(Localizations.localeOf(context), message.createdAt),
            style: NoWaveTypography.meta(context),
          ),
        ],
      ),
    );
  }
}

class _ThreadStatus extends StatelessWidget {
  const _ThreadStatus({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

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
