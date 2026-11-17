import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_list_actions.dart';
import 'package:belog/features/blog/presentation/editor/structured_insert_page.dart';
import 'package:flutter/material.dart';

/// Local list management uses the parent coordinator, not a second writer.
/// Every row action captures a body snapshot because item indices are not IDs.
class StructuredListPage extends StatefulWidget {
  const StructuredListPage({
    super.key,
    required this.session,
    required this.blockId,
  });
  final LocalStructuredSession session;
  final String blockId;

  @override
  State<StructuredListPage> createState() => _StructuredListPageState();
}

class _PendingRemoval {
  _PendingRemoval(this.body, this.index);
  final StructuredArticleDraft body;
  final int index;
}

class _StructuredListPageState extends State<StructuredListPage>
    with WidgetsBindingObserver {
  late final StreamSubscription<LocalStructuredState> _subscription;
  _PendingRemoval? _pendingRemoval;
  bool _reading = false;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.changes.listen((state) {
      final pending = _pendingRemoval;
      if (pending != null && !identical(state.body, pending.body)) {
        _pendingRemoval = null;
      }
      if (mounted && !_reading) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.session.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingRemoval = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  Map<String, Object?>? _list(StructuredArticleDraft? body) {
    if (body == null) return null;
    final blocks = body.blocks.where((block) => block['id'] == widget.blockId);
    if (blocks.length != 1 || blocks.single['type'] != 'list') return null;
    return blocks.single;
  }

  bool _current(StructuredArticleDraft body) {
    final state = widget.session.state;
    return !_busy &&
        state.phase == LocalStructuredPhase.editing &&
        identical(body, state.body) &&
        _list(body) != null;
  }

  void _move(StructuredArticleDraft body, int index, int destination) {
    if (!_current(body)) return;
    try {
      final action = StructuredListMove(
        source: body,
        blockId: widget.blockId,
        index: index,
        destination: destination,
      );
      final accepted = widget.session.edit(action.apply);
      if (mounted) setState(() => _error = !accepted);
    } on FormatException {
      if (mounted) setState(() => _error = true);
    } on ArgumentError {
      if (mounted) setState(() => _error = true);
    } on StateError {
      if (mounted) setState(() => _error = true);
    }
  }

  void _remove(StructuredArticleDraft body, int index) {
    if (!_current(body)) return;
    _pendingRemoval = _PendingRemoval(body, index);
    unawaited(_confirmRemoval());
  }

  Future<void> _confirmRemoval() async {
    setState(() => _busy = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredListRemoveTitle,
      message: l10n.structuredListRemoveBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredListRemove,
    );
    if (!mounted) return;
    final pending = _pendingRemoval;
    _pendingRemoval = null;
    setState(() => _busy = false);
    if (!confirmed || pending == null || !_current(pending.body)) return;
    try {
      final accepted = widget.session.edit(
        StructuredListRemove(
          source: pending.body,
          blockId: widget.blockId,
          index: pending.index,
        ).apply,
      );
      if (mounted) setState(() => _error = !accepted);
    } on FormatException {
      if (mounted) setState(() => _error = true);
    } on ArgumentError {
      if (mounted) setState(() => _error = true);
    } on StateError {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _insert(StructuredArticleDraft body, int index) async {
    if (!_current(body)) return;
    final seed = StructuredInsertSeed(body);
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredInsertPage(
            session: widget.session,
            anchorId: widget.blockId,
            itemIndex: index,
            seed: seed,
          ),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(BuildContext context, LocalStructuredState state) {
    final l10n = context.l10n;
    if (state.phase == LocalStructuredPhase.saveFailed) {
      return l10n.structuredSaveFailure;
    }
    if (state.phase == LocalStructuredPhase.conflict) {
      return l10n.structuredConflict;
    }
    if (state.saving || state.hasUnsavedChanges) return l10n.structuredSaving;
    return state.recoveryAvailable
        ? l10n.structuredSaved
        : l10n.structuredNotSaved;
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final LocalStructuredState state;
    try {
      state = widget.session.state;
    } finally {
      _reading = false;
    }
    final body = state.body;
    final list = _list(body);
    final l10n = context.l10n;
    final editable = !_busy && state.phase == LocalStructuredPhase.editing;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredListTitle)),
      body: SafeArea(
        child: list == null || body == null
            ? Center(
                child: Text(
                  state.phase == LocalStructuredPhase.invalidated ||
                          state.phase == LocalStructuredPhase.closed
                      ? l10n.structuredSessionChanged
                      : state.phase == LocalStructuredPhase.conflict
                      ? l10n.structuredConflict
                      : state.phase == LocalStructuredPhase.saveFailed
                      ? l10n.structuredSaveFailure
                      : l10n.structuredLocalFailure,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                children: [
                  Text(l10n.structuredListIntro),
                  const SizedBox(height: NoWaveSpacing.small),
                  Semantics(
                    liveRegion: true,
                    child: Text(_status(context, state)),
                  ),
                  if (state.phase == LocalStructuredPhase.saveFailed)
                    TextButton(
                      onPressed: widget.session.retrySave,
                      child: Text(l10n.actionRetry),
                    ),
                  if (_error)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredListActionFailed),
                    ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  for (
                    var index = 0;
                    index < (list['items'] as List).length;
                    index++
                  )
                    _ListItemCard(
                      position: index + 1,
                      text: (list['items'] as List)[index] as String,
                      ordered: list['ordered'] as bool,
                      enabled: editable,
                      canMoveUp: index > 0,
                      canMoveDown: index + 1 < (list['items'] as List).length,
                      canRemove: (list['items'] as List).length > 1,
                      canInsert: (list['items'] as List).length < 100,
                      onUp: () => _move(body, index, index - 1),
                      onDown: () => _move(body, index, index + 1),
                      onRemove: () => _remove(body, index),
                      onInsert: () => _insert(body, index + 1),
                    ),
                  if ((list['items'] as List).length >= 100)
                    Text(l10n.structuredListLimit),
                  if ((list['items'] as List).length == 1)
                    Text(l10n.structuredListLastItem),
                ],
              ),
      ),
    );
  }
}

class _ListItemCard extends StatelessWidget {
  const _ListItemCard({
    required this.position,
    required this.text,
    required this.ordered,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
    required this.canInsert,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
    required this.onInsert,
  });
  final int position;
  final String text;
  final bool ordered;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;
  final bool canInsert;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safeText = isWellFormedUtf16(text)
        ? text
        : l10n.structuredInlineUnsupported;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.structuredListItem} $position',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(ordered ? '$position. $safeText' : '• $safeText'),
            Wrap(
              children: [
                IconButton(
                  tooltip: l10n.structuredListMoveUp,
                  onPressed: enabled && canMoveUp ? onUp : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: l10n.structuredListMoveDown,
                  onPressed: enabled && canMoveDown ? onDown : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: l10n.structuredListRemove,
                  onPressed: enabled && canRemove ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: l10n.structuredListInsertAfter,
                  onPressed: enabled && canInsert ? onInsert : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
