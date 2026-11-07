import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/presentation/blocs/publish_queue/publish_queue_cubit.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// The publishes this device still owes the server (issue #23).
///
/// Each row is one intent: what it says, how many times it was tried, why the
/// last attempt failed, and what the user can do about it. Sending stays in the
/// runner, so this screen never publishes anything the background retry would
/// not; it only starts a send, retries one entry, or drops one.
class PublishQueuePage extends StatelessWidget {
  const PublishQueuePage({super.key, this.cubit});

  /// Injected by tests; production reads the shared instance.
  final PublishQueueCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final injected = cubit;
    if (injected != null) {
      return BlocProvider<PublishQueueCubit>.value(
        value: injected,
        child: const _PublishQueueView(),
      );
    }
    return BlocProvider<PublishQueueCubit>(
      create: (_) => GetIt.instance<PublishQueueCubit>(),
      child: const _PublishQueueView(),
    );
  }
}

class _PublishQueueView extends StatelessWidget {
  const _PublishQueueView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.publishQueueTitle),
        centerTitle: true,
        actions: [
          BlocBuilder<PublishQueueCubit, PublishQueueState>(
            builder: (context, state) {
              if (state is! PublishQueueLoaded ||
                  !state.signedIn ||
                  state.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: state.sending
                    ? null
                    : () => context.read<PublishQueueCubit>().sendNow(),
                child: Text(context.l10n.publishQueueSendNow),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<PublishQueueCubit, PublishQueueState>(
        builder: (context, state) {
          if (state is PublishQueueLoading) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: context.l10n.loading,
              ),
            );
          }
          if (state is PublishQueueFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.large),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(localizedFailure(context.l10n, state.failure)),
                    const SizedBox(height: 12),
                    NoWaveButton(
                      label: context.l10n.publishQueueRetry,
                      variant: NoWaveButtonVariant.secondary,
                      onPressed: () => context.read<PublishQueueCubit>().load(),
                    ),
                  ],
                ),
              ),
            );
          }
          final loaded = state as PublishQueueLoaded;
          if (!loaded.signedIn) {
            return _QueueEmpty(
              title: context.l10n.publishQueueNoSession,
              body: context.l10n.publishQueueMenuHint,
              actionLabel: context.l10n.publishQueueSignIn,
              onAction: () => context.push('/login'),
            );
          }
          if (loaded.isEmpty) {
            return _QueueEmpty(
              title: context.l10n.publishQueueEmptyTitle,
              body: context.l10n.publishQueueEmptyBody,
            );
          }
          return RefreshIndicator(
            // Pulling the list re-sends what is due, which is what a reader of
            // this screen wants after reconnecting.
            onRefresh: () => context.read<PublishQueueCubit>().sendNow(),
            child: ListView.separated(
              padding: const EdgeInsets.all(NoWaveSpacing.medium),
              itemCount: loaded.entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _QueueEntryCard(
                entry: loaded.entries[index],
                sending: loaded.sending,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QueueEmpty extends StatelessWidget {
  const _QueueEmpty({
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

class _QueueEntryCard extends StatelessWidget {
  const _QueueEntryCard({required this.entry, required this.sending});

  final PublishQueueEntry entry;

  /// A drain is in flight, so per-entry actions wait their turn.
  final bool sending;

  String _statusLabel(BuildContext context) => switch (entry.status) {
    PublishQueueStatus.queued => context.l10n.publishQueueStatusQueued,
    PublishQueueStatus.uploading => context.l10n.publishQueueStatusUploading,
    PublishQueueStatus.failed => context.l10n.publishQueueStatusFailed,
  };

  Future<void> _remove(BuildContext context) async {
    final removed = await context.read<PublishQueueCubit>().remove(entry.id);
    if (!context.mounted) return;
    if (removed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.publishQueueRemoved)));
    }
  }

  Future<void> _retry(BuildContext context) async {
    final queued = await context.read<PublishQueueCubit>().retry(entry.id);
    if (!context.mounted) return;
    if (queued) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.publishQueueRetryQueued)),
      );
    }
  }

  /// Opens the editor with this entry's text and cover. An edit entry opens it
  /// in update mode for the article it targets. The editor deletes the entry
  /// once the new attempt is sent or is queued again, so this screen reloads on
  /// return instead of assuming either outcome.
  Future<void> _resumeEditing(BuildContext context) async {
    await context.push<bool>('/profile/editor', extra: entry);
    if (!context.mounted) return;
    await context.read<PublishQueueCubit>().load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = entry.title.trim().isEmpty
        ? context.l10n.publishQueueUntitled
        : entry.title.trim();
    final lastError = entry.lastErrorCode;
    final canRetry = !sending && entry.status != PublishQueueStatus.uploading;
    // Only a stopped entry can be re-edited: a queued one may be claimed by
    // the drain mid-edit, and an uploading one is already on the wire.
    final canResume = !sending && entry.status == PublishQueueStatus.failed;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: NoWaveSpacing.small),
                _StatusChip(label: _statusLabel(context), entry: entry),
              ],
            ),
            if (entry.kind == PublishQueueKind.edit) ...[
              const SizedBox(height: NoWaveSpacing.xs),
              Text(
                context.l10n.publishQueueEditEntry,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (entry.attempts > 0) ...[
              const SizedBox(height: NoWaveSpacing.small),
              Text(
                context.l10n.publishQueueAttempts(entry.attempts),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (lastError != null && lastError.isNotEmpty) ...[
              const SizedBox(height: NoWaveSpacing.xs),
              Text(
                context.l10n.publishQueueLastError(lastError),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: NoWaveSpacing.small),
            // A wrap, not a row: three actions must still fit at 320 dp and
            // 2x text without an overflow banner.
            Wrap(
              spacing: NoWaveSpacing.small,
              children: [
                if (canResume)
                  TextButton(
                    onPressed: () => _resumeEditing(context),
                    child: Text(context.l10n.publishQueueResumeEditing),
                  ),
                TextButton(
                  onPressed: canRetry ? () => _retry(context) : null,
                  child: Text(context.l10n.publishQueueRetry),
                ),
                TextButton(
                  onPressed: () => _remove(context),
                  child: Text(context.l10n.publishQueueRemove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.entry});

  final String label;
  final PublishQueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color background = scheme.secondaryContainer;
    Color foreground = scheme.onSecondaryContainer;
    if (entry.status == PublishQueueStatus.uploading) {
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
    } else if (entry.status == PublishQueueStatus.failed) {
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
