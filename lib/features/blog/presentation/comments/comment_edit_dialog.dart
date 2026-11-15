import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_edit_result.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/comments/comment_edit_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Editor for a single, known plain-text comment. This editor is intentionally
/// separate from the create composer: cancelling it cannot alter a reply draft
/// or its idempotency key.
class CommentEditDialog extends StatefulWidget {
  const CommentEditDialog({
    super.key,
    required this.comment,
    required this.bloc,
    required this.fence,
  });

  final Comment comment;
  final CommentBloc bloc;
  final NowaveSessionFence fence;

  @override
  State<CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<CommentEditDialog> {
  late final TextEditingController _text;
  StreamSubscription<void>? _identitySubscription;
  bool _saving = false;
  bool _invalidated = false;
  bool _uncertain = false;
  CommentEditResult? _lastResult;
  bool _allowPop = false;
  bool _confirmingDiscard = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.comment.content);
    _identitySubscription = widget.bloc.sessionIdentity?.identityChanges.listen(
      (_) {
        // This signal is synchronous. Hide the old account's text immediately,
        // even if the ordinary auth state has not yet been emitted.
        _text.clear();
        if (mounted) {
          setState(() {
            _invalidated = true;
            _saving = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _identitySubscription?.cancel();
    _text.dispose();
    super.dispose();
  }

  bool get _canSave {
    final content = _text.text.trim();
    return !_saving &&
        !_invalidated &&
        !_uncertain &&
        content.isNotEmpty &&
        content.length <= CommentBloc.maxContentLength &&
        content != widget.comment.content;
  }

  bool get _dirty => _text.text != widget.comment.content;

  /// Discard is explicit for a modified draft. In particular, after an unknown
  /// result the reader can copy the text before closing or refreshing.
  Future<void> _cancel({bool refresh = false}) async {
    if (_saving || _confirmingDiscard) return;
    if (_dirty && !_invalidated) {
      _confirmingDiscard = true;
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.commentEditDiscardTitle),
          content: Text(context.l10n.commentEditDiscardBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.commentEditKeep),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.commentEditDiscard),
            ),
          ],
        ),
      );
      _confirmingDiscard = false;
      if (!mounted || discard != true) return;
    }
    if (!mounted) return;
    if (refresh && !widget.bloc.isClosed) {
      widget.bloc.add(const CommentsRequested());
    }
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  /// Clipboard use is explicit, never automatic. It lets a reader preserve a
  /// correction before refreshing an uncertain write without sending it again.
  Future<void> _copyDraft() async {
    if (_invalidated || _text.text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: _text.text));
      if (mounted && !_invalidated) setState(() => _copied = true);
    } catch (_) {
      if (mounted && !_invalidated) setState(() => _copied = false);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _lastResult = null;
    });
    final result = await widget.bloc.editPlainComment(
      original: widget.comment,
      text: _text.text,
      fence: widget.fence,
    );
    if (!mounted) return;
    if (result.status == CommentEditStatus.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _lastResult = result;
      if (result.status == CommentEditStatus.sessionChanged) {
        _invalidated = true;
        _text.clear();
      }
      if (result.status == CommentEditStatus.outcomeUnknown ||
          result.status == CommentEditStatus.stale) {
        _uncertain = true;
      }
    });
  }

  String? _message(BuildContext context) {
    if (_invalidated) return context.l10n.commentEditSessionChanged;
    final result = _lastResult;
    if (result == null) return null;
    switch (result.status) {
      case CommentEditStatus.stale:
        return context.l10n.commentEditStale;
      case CommentEditStatus.outcomeUnknown:
        return context.l10n.commentEditUnknown;
      case CommentEditStatus.sessionChanged:
        return context.l10n.commentEditSessionChanged;
      case CommentEditStatus.rejected:
        final failure = result.failure;
        if (failure == null) return context.l10n.commentEditFailed;
        if (failure.code == 'comments.editUnavailable') {
          return context.l10n.commentEditUnavailable;
        }
        return localizedFailure(context.l10n, failure);
      case CommentEditStatus.saved:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message(context);
    return PopScope(
      canPop: !_saving && (_allowPop || !_dirty || _invalidated),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _cancel();
      },
      child: AlertDialog(
        title: Text(context.l10n.commentEditTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.commentEditConcurrencyWarning),
              const SizedBox(height: NoWaveSpacing.medium),
              TextField(
                controller: _text,
                enabled: !_invalidated,
                readOnly: _saving || _uncertain,
                maxLength: CommentBloc.maxContentLength,
                minLines: 2,
                maxLines: 6,
                autofocus: true,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {
                  _lastResult = null;
                  _copied = false;
                }),
                decoration: InputDecoration(
                  labelText: context.l10n.commentEditInput,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_dirty && !_invalidated)
                CommentEditPreview(
                  original: widget.comment.content,
                  draft: _text.text,
                ),
              if (_uncertain && !_invalidated)
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copyDraft,
                      icon: const Icon(Icons.copy),
                      label: Text(context.l10n.commentEditCopyDraft),
                    ),
                    if (_copied)
                      Expanded(child: Text(context.l10n.commentEditCopied)),
                  ],
                ),
              if (message != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _cancel,
            child: Text(context.l10n.actionCancel),
          ),
          if (_uncertain && !_invalidated)
            TextButton(
              onPressed: _saving ? null : () => _cancel(refresh: true),
              child: Text(context.l10n.commentEditRefresh),
            ),
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              _saving
                  ? context.l10n.commentEditSaving
                  : context.l10n.commentEditSave,
            ),
          ),
        ],
      ),
    );
  }
}
