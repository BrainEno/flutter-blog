import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/data/publication_outbox.dart';
import 'package:belog/features/blog/domain/entities/queued_publication.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// Local publication requests for the currently signed-in account.
class PublicationOutboxPage extends StatefulWidget {
  const PublicationOutboxPage({super.key, this.outbox});

  final PublicationOutbox? outbox;

  @override
  State<PublicationOutboxPage> createState() => _PublicationOutboxPageState();
}

class _PublicationOutboxPageState extends State<PublicationOutboxPage> {
  late final PublicationOutbox _outbox;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _outbox = widget.outbox ?? GetIt.instance<PublicationOutbox>();
    _outbox.addListener(_reload);
  }

  @override
  void dispose() {
    _outbox.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.outboxTitle)),
      body: BlocBuilder<AppUserCubit, AppUserState>(
        builder: (context, state) {
          final ownerId = state is AppUserLoggedIn ? state.user.id : '';
          return FutureBuilder<List<QueuedPublication>>(
            // Do not retain the previous account's snapshot during a switch.
            key: ValueKey('$ownerId:$_revision'),
            future: _outbox.list(ownerId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(l10n.outboxErrorServer));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l10n.outboxIntro),
                  if (_outbox.online == false) ...[
                    const SizedBox(height: 12),
                    Text(l10n.outboxOffline),
                  ],
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text(l10n.outboxEmpty)),
                    )
                  else
                    for (final item in items) _itemCard(context, item),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _itemCard(BuildContext context, QueuedPublication item) {
    final l10n = context.l10n;
    final error = _errorMessage(l10n, item);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              _status(l10n, item.status),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text('${l10n.outboxAttempts}: ${item.attemptCount}'),
            if (item.nextAttemptAt != null)
              Text('${l10n.outboxNextAttempt}: ${_date(item.nextAttemptAt!)}'),
            if (item.hasCover) Text(l10n.outboxCoverAttached),
            if (item.possibleOrphan) Text(l10n.outboxOrphanWarning),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (item.canEdit)
                  TextButton(
                    onPressed: () => _edit(item),
                    child: Text(l10n.outboxEdit),
                  ),
                if (item.canEdit && item.hasCover)
                  TextButton(
                    onPressed: () => _removeCover(item),
                    child: Text(l10n.outboxRemoveCover),
                  ),
                if (item.status == PublicationStatus.failed &&
                    !item.articleOutcomeUncertain)
                  TextButton(
                    onPressed: () => _retry(item),
                    child: Text(l10n.actionRetry),
                  ),
                if (item.articleOutcomeUncertain)
                  TextButton(
                    onPressed: () => _check(item),
                    child: Text(l10n.outboxCheck),
                  ),
                if (item.status == PublicationStatus.published &&
                    item.publishedSlug != null)
                  TextButton(
                    onPressed: () =>
                        context.push('/profile/view/${item.publishedSlug}'),
                    child: Text(l10n.outboxOpenArticle),
                  ),
                if (item.status != PublicationStatus.uploading &&
                    !item.articleOutcomeUncertain)
                  TextButton(
                    onPressed: () => _remove(item),
                    child: Text(
                      item.status == PublicationStatus.published
                          ? l10n.outboxRemoveRecord
                          : l10n.outboxCancelItem,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _status(AppLocalizations l10n, PublicationStatus status) =>
      switch (status) {
        PublicationStatus.queued => l10n.outboxQueued,
        PublicationStatus.uploading => l10n.outboxUploading,
        PublicationStatus.failed => l10n.outboxFailed,
        PublicationStatus.published => l10n.outboxPublished,
      };

  String? _errorMessage(AppLocalizations l10n, QueuedPublication item) {
    if (item.articleOutcomeUncertain) return l10n.outboxArticleUnknown;
    if (item.phase == PublicationPhase.mediaUncertain) {
      return l10n.outboxMediaUnknown;
    }
    return switch (item.lastErrorCode) {
      'auth.ownerUnavailable' => l10n.outboxErrorAuth,
      'article.validation' ||
      'media.validation' ||
      'media.missing' => l10n.outboxErrorValidation,
      'network.unavailable' => l10n.outboxErrorNetwork,
      'server.unavailable' => l10n.outboxErrorServer,
      _ => null,
    };
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _retry(QueuedPublication item) async {
    final l10n = context.l10n;
    final uncertain = item.phase == PublicationPhase.mediaUncertain;
    if (uncertain &&
        !await _confirm(
          l10n.actionRetry,
          l10n.outboxRetryMediaConfirm,
          l10n.actionRetry,
        )) {
      return;
    }
    if (!mounted) return;
    final ok = await _outbox.retry(
      item.ownerId,
      item.id,
      acceptMediaReupload: uncertain,
    );
    if (mounted && !ok) showSnackBar(context, l10n.outboxChanged);
  }

  Future<void> _check(QueuedPublication item) async {
    final l10n = context.l10n;
    final confirmed = await _outbox.reconcile(item.ownerId, item.id);
    if (mounted && !confirmed) {
      showSnackBar(context, l10n.outboxCheckUnconfirmed);
    }
  }

  Future<void> _removeCover(QueuedPublication item) async {
    final l10n = context.l10n;
    final message = item.mayHaveRemoteOrphan
        ? '${l10n.outboxCoverConfirm}\n\n${l10n.outboxOrphanWarning}'
        : l10n.outboxCoverConfirm;
    if (!await _confirm(
      l10n.outboxRemoveCover,
      message,
      l10n.outboxRemoveCover,
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await _outbox.removeCover(
      item.ownerId,
      item.id,
      acceptPossibleOrphan: item.mayHaveRemoteOrphan,
    );
    if (mounted && !ok) showSnackBar(context, l10n.outboxChanged);
  }

  Future<void> _remove(QueuedPublication item) async {
    final l10n = context.l10n;
    final message = item.mayHaveRemoteOrphan
        ? '${l10n.outboxRemoveConfirm}\n\n${l10n.outboxOrphanWarning}'
        : l10n.outboxRemoveConfirm;
    if (!await _confirm(l10n.actionDelete, message, l10n.actionDelete)) return;
    if (!mounted) return;
    final ok = await _outbox.remove(
      item.ownerId,
      item.id,
      acceptPossibleOrphan: item.mayHaveRemoteOrphan,
    );
    if (mounted && !ok) showSnackBar(context, l10n.outboxChanged);
  }

  Future<void> _edit(QueuedPublication item) async {
    final l10n = context.l10n;
    final title = TextEditingController(text: item.title);
    final content = TextEditingController(text: item.content);
    final tags = TextEditingController(text: item.tags.join(', '));
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.outboxEditTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: l10n.outboxTitleField),
              ),
              TextField(
                controller: content,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: l10n.outboxBodyField),
              ),
              TextField(
                controller: tags,
                decoration: InputDecoration(labelText: l10n.outboxTagsField),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.actionSaveChanges),
          ),
        ],
      ),
    );
    final titleText = title.text;
    final contentText = content.text;
    final tagList = tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    title.dispose();
    content.dispose();
    tags.dispose();
    if (result != true || !mounted) return;
    final ok = await _outbox.edit(
      item.ownerId,
      item.id,
      title: titleText,
      content: contentText,
      tags: tagList,
    );
    if (mounted && !ok) showSnackBar(context, l10n.outboxSaveFailed);
  }
}
