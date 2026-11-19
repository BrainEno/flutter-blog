import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_body_history.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_card.dart';
import 'package:belog/features/blog/presentation/editor/structured_history_patch_page.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/material.dart';

/// A one-shot, memory-only route handoff. The owner and receiver clear their
/// references at route exit; it is neither a saved record nor a CAS token.
class StructuredBodyHistorySeed {
  StructuredBodyHistorySeed(this._view);
  StructuredHistoryView? _view;
  StructuredHistoryView? take() {
    final view = _view;
    _view = null;
    return view;
  }

  void clear() => _view = null;
}

/// Preview a session checkpoint against the current body. A confirmation
/// applies it only through the original session's fenced local CAS writer.
/// No server read/write or recovery-row deletion is performed by this route.
class StructuredBodyHistoryPage extends StatefulWidget {
  const StructuredBodyHistoryPage({
    super.key,
    required this.session,
    required this.seed,
  });
  final LocalStructuredSession session;
  final StructuredBodyHistorySeed seed;

  @override
  State<StructuredBodyHistoryPage> createState() =>
      _StructuredBodyHistoryPageState();
}

class _StructuredBodyHistoryPageState extends State<StructuredBodyHistoryPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredHistoryView? _view;
  StructuredDocumentComparison? _comparison;
  int? _selectedId;
  bool _reading = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final candidate = widget.seed.take();
    final state = widget.session.state;
    if (candidate != null && _matches(candidate, state)) {
      _view = candidate;
      final index = candidate.canUndo
          ? candidate.currentIndex - 1
          : candidate.currentIndex;
      _select(candidate.entries[index].id);
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  bool _matches(StructuredHistoryView view, LocalStructuredState state) =>
      state.phase == LocalStructuredPhase.editing &&
      identical(state.body, view.current.body);

  void _clear() {
    _view = null;
    _comparison = null;
    _selectedId = null;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onState(LocalStructuredState state) {
    final view = _view;
    if (view != null && !_matches(view, state)) {
      _clear();
      if (mounted && !_reading) setState(() {});
    }
  }

  void _select(int id) {
    final view = _view;
    if (view == null) return;
    final target = view.entries.where((entry) => entry.id == id);
    if (target.length != 1) return;
    _selectedId = id;
    _comparison = StructuredDocumentComparison.between(
      view.current.body,
      target.single.body,
    );
  }

  Future<void> _restore() async {
    final generation = _view?.generation;
    final currentId = _view?.current.id;
    final selected = _selectedId;
    if (_confirming ||
        generation == null ||
        currentId == null ||
        selected == null ||
        selected == currentId) {
      return;
    }
    setState(() => _confirming = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredHistoryConfirmTitle,
      message: l10n.structuredHistoryConfirmBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredHistoryRestore,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    final view = _view;
    if (!confirmed ||
        view == null ||
        view.generation != generation ||
        selected != _selectedId) {
      return;
    }
    // The session independently checks identity, current body and generation.
    // In particular, a stale dialog never applies to a later body.
    final accepted = widget.session.selectBodyHistory(
      current: view.current.body,
      generation: view.generation,
      entryId: selected,
    );
    if (!mounted) return;
    if (accepted) {
      Navigator.of(context).pop();
    } else {
      _clear();
      setState(() {});
    }
  }

  StructuredHistoryPatchSeed? _patchSeed() {
    final view = _view;
    final selected = _selectedId;
    if (view == null || selected == null || selected == view.current.id) {
      return null;
    }
    return StructuredHistoryPatchSeed(view, selected);
  }

  Future<void> _openPatch() async {
    if (_confirming) return;
    final seed = _patchSeed();
    if (seed == null) return;
    setState(() => _confirming = true);
    try {
      final applied = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) =>
              StructuredHistoryPatchPage(session: widget.session, seed: seed),
        ),
      );
      if (mounted && applied == true) Navigator.of(context).pop();
    } finally {
      seed.clear();
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _restoreBlock(String blockId) async {
    final generation = _view?.generation;
    final currentId = _view?.current.id;
    final selected = _selectedId;
    if (_confirming ||
        generation == null ||
        currentId == null ||
        selected == null ||
        selected == currentId) {
      return;
    }
    setState(() => _confirming = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredHistoryBlockConfirmTitle,
      message: l10n.structuredHistoryBlockConfirmBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredHistoryBlockRestore,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    final view = _view;
    if (!confirmed ||
        view == null ||
        view.generation != generation ||
        selected != _selectedId) {
      return;
    }
    final result = widget.session.restoreBodyHistoryBlock(
      current: view.current.body,
      generation: view.generation,
      entryId: selected,
      blockId: blockId,
    );
    if (!mounted) return;
    switch (result) {
      case LocalHistoryBlockRestoreResult.accepted:
        Navigator.of(context).pop();
      case LocalHistoryBlockRestoreResult.invalid:
        showSnackBar(context, context.l10n.structuredHistoryBlockInvalid);
      case LocalHistoryBlockRestoreResult.stale:
      case LocalHistoryBlockRestoreResult.unchanged:
        _clear();
        setState(() {});
    }
  }

  @override
  void dispose() {
    widget.seed.clear();
    _clear();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  String _entryLabel(
    BuildContext context,
    StructuredHistoryView view,
    int index,
  ) {
    final l10n = context.l10n;
    final position = index == view.currentIndex
        ? l10n.structuredHistoryCurrent
        : index < view.currentIndex
        ? l10n.structuredHistoryPast
        : l10n.structuredHistoryFuture;
    return '${l10n.structuredHistoryStep} ${index + 1} · $position';
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
    final captured = _view;
    if (captured != null && !_matches(captured, state)) _clear();
    final view = _view;
    final comparison = _comparison;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.structuredHistoryTitle)),
      body: SafeArea(
        child: view == null || comparison == null
            ? Center(child: Text(context.l10n.structuredHistoryStale))
            : _content(context, view, comparison),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    StructuredHistoryView view,
    StructuredDocumentComparison comparison,
  ) {
    final l10n = context.l10n;
    final changed = comparison.entries
        .where((entry) => entry.changed)
        .toList(growable: false);
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: changed.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          final change = changed[index - 1];
          return Column(
            key: ValueKey(change.id),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StructuredComparisonCard(change: change, comparison: comparison),
              if (change.modified && !change.added && !change.removed)
                OutlinedButton.icon(
                  onPressed: _confirming
                      ? null
                      : () => _restoreBlock(change.id),
                  icon: const Icon(Icons.restore_page),
                  label: Text(l10n.structuredHistoryBlockRestore),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.structuredHistoryIntro),
            const SizedBox(height: NoWaveSpacing.small),
            Text(l10n.structuredHistoryLimits),
            if (view.truncated) Text(l10n.structuredHistoryTruncated),
            const SizedBox(height: NoWaveSpacing.medium),
            DropdownButtonFormField<int>(
              initialValue: _selectedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.structuredHistoryChoose,
              ),
              items: [
                for (var i = 0; i < view.entries.length; i++)
                  DropdownMenuItem(
                    value: view.entries[i].id,
                    child: Text(_entryLabel(context, view, i)),
                  ),
              ],
              onChanged: _confirming
                  ? null
                  : (value) {
                      if (value != null) setState(() => _select(value));
                    },
            ),
            const SizedBox(height: NoWaveSpacing.medium),
            Text(
              l10n.structuredHistoryDirection,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${l10n.structuredCompareAdded}: ${comparison.addedCount} · ${l10n.structuredCompareRemoved}: ${comparison.removedCount} · ${l10n.structuredCompareModified}: ${comparison.modifiedCount} · ${l10n.structuredCompareMoved}: ${comparison.movedCount}',
            ),
            Text(l10n.structuredCompareCountsNote),
            if (comparison.versionChanged)
              Text(l10n.structuredCompareVersionChanged),
            if (changed.isEmpty) Text(l10n.structuredHistoryNoBodyChanges),
            const SizedBox(height: NoWaveSpacing.medium),
            OutlinedButton.icon(
              onPressed: _confirming || _selectedId == view.current.id
                  ? null
                  : _openPatch,
              icon: const Icon(Icons.playlist_add_check),
              label: Text(l10n.structuredHistoryPatchTitle),
            ),
            FilledButton.tonalIcon(
              onPressed: _confirming || _selectedId == view.current.id
                  ? null
                  : _restore,
              icon: const Icon(Icons.restore),
              label: Text(l10n.structuredHistoryRestore),
            ),
            const SizedBox(height: NoWaveSpacing.medium),
          ],
        );
      },
    );
  }
}
