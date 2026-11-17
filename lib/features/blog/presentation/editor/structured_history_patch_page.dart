import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_body_history.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/domain/editing/structured_history_patch.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_card.dart';
import 'package:flutter/material.dart';

class StructuredHistoryPatchSeed {
  StructuredHistoryPatchSeed(this._view, this._entryId);
  StructuredHistoryView? _view;
  int? _entryId;
  (StructuredHistoryView, int)? take() {
    final view = _view;
    final entryId = _entryId;
    clear();
    return view == null || entryId == null ? null : (view, entryId);
  }

  void clear() {
    _view = null;
    _entryId = null;
  }
}

/// Review a bounded subset of shared, modified blocks before applying them as
/// one local CAS edit. It does not choose insertions, removals or block moves.
class StructuredHistoryPatchPage extends StatefulWidget {
  const StructuredHistoryPatchPage({
    super.key,
    required this.session,
    required this.seed,
  });
  final LocalStructuredSession session;
  final StructuredHistoryPatchSeed seed;

  @override
  State<StructuredHistoryPatchPage> createState() =>
      _StructuredHistoryPatchPageState();
}

class _StructuredHistoryPatchPageState
    extends State<StructuredHistoryPatchPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredHistoryView? _view;
  StructuredHistoryEntry? _source;
  List<StructuredBlockChange> _candidates = const [];
  final Set<String> _selected = {};
  StructuredHistoryPatch? _plan;
  StructuredDocumentComparison? _preview;
  bool _invalid = false;
  bool _reading = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed.take();
    final state = widget.session.state;
    if (seed != null && _matches(seed.$1, state)) {
      final targets = seed.$1.entries.where((entry) => entry.id == seed.$2);
      if (targets.length == 1 && seed.$2 != seed.$1.current.id) {
        _view = seed.$1;
        _source = targets.single;
        final diff = StructuredDocumentComparison.between(
          seed.$1.current.body,
          targets.single.body,
        );
        _candidates = List.unmodifiable(
          diff.entries.where((entry) => entry.modified),
        );
      }
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  bool _matches(StructuredHistoryView view, LocalStructuredState state) =>
      state.phase == LocalStructuredPhase.editing &&
      identical(state.body, view.current.body);

  void _clear() {
    _view = null;
    _source = null;
    _candidates = const [];
    _selected.clear();
    _plan = null;
    _preview = null;
    _invalid = false;
  }

  void _onState(LocalStructuredState state) {
    final view = _view;
    if (view != null && !_matches(view, state)) {
      _clear();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted && !_reading) setState(() {});
    }
  }

  void _setSelected(String id, bool value) {
    if (value) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
    _plan = null;
    _preview = null;
    _invalid = false;
  }

  void _prepare() {
    final view = _view;
    final source = _source;
    if (view == null || source == null || _selected.isEmpty) return;
    try {
      final plan = StructuredHistoryPatch.prepare(
        current: view.current.body,
        source: source.body,
        blockIds: _selected,
      );
      _plan = plan;
      _preview = StructuredDocumentComparison.between(
        plan.current,
        plan.result,
      );
      _invalid = false;
    } on FormatException {
      _plan = null;
      _preview = null;
      _invalid = true;
    }
  }

  Future<void> _apply() async {
    final generation = _view?.generation;
    final entryId = _source?.id;
    if (_confirming || generation == null || entryId == null || _plan == null) {
      return;
    }
    setState(() => _confirming = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredHistoryPatchConfirmTitle,
      message: l10n.structuredHistoryPatchConfirmBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredHistoryPatchApply,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    final view = _view;
    final source = _source;
    final plan = _plan;
    if (!confirmed ||
        view == null ||
        source == null ||
        plan == null ||
        view.generation != generation ||
        source.id != entryId) {
      return;
    }
    final result = widget.session.restoreBodyHistoryBlocks(
      current: view.current.body,
      generation: view.generation,
      entryId: source.id,
      blockIds: plan.blockIds,
    );
    if (!mounted) return;
    switch (result) {
      case LocalHistoryBlockRestoreResult.accepted:
        // Return through the history page, whose captured view is now stale.
        Navigator.of(context).pop(true);
      case LocalHistoryBlockRestoreResult.invalid:
        setState(() {
          _plan = null;
          _preview = null;
          _invalid = true;
        });
      case LocalHistoryBlockRestoreResult.stale:
      case LocalHistoryBlockRestoreResult.unchanged:
        setState(_clear);
    }
  }

  @override
  void dispose() {
    widget.seed.clear();
    _clear();
    unawaited(_subscription.cancel());
    super.dispose();
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
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.structuredHistoryPatchTitle)),
      body: SafeArea(
        child: view == null || source == null
            ? Center(child: Text(context.l10n.structuredHistoryStale))
            : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview;
    final changed =
        preview?.entries
            .where((entry) => entry.changed)
            .toList(growable: false) ??
        const <StructuredBlockChange>[];
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount:
          1 + _candidates.length + (preview == null ? 0 : 1 + changed.length),
      itemBuilder: (context, index) {
        if (index == 0) return _intro(context);
        if (index <= _candidates.length) {
          final candidate = _candidates[index - 1];
          final id = isWellFormedUtf16(candidate.id)
              ? candidate.id
              : l10n.structuredInlineUnsupported;
          return CheckboxListTile(
            key: ValueKey('history-select-${candidate.id}'),
            value: _selected.contains(candidate.id),
            onChanged: _confirming
                ? null
                : (value) =>
                      setState(() => _setSelected(candidate.id, value == true)),
            title: Text('${l10n.structuredCompareBlockId}: $id'),
            subtitle: Text(
              '${l10n.structuredCompareBeforePosition}: ${candidate.beforeIndex! + 1}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          );
        }
        if (preview == null) return const SizedBox.shrink();
        final previewIndex = index - _candidates.length - 1;
        if (previewIndex == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: NoWaveSpacing.medium),
              Text(
                l10n.structuredHistoryPatchPreviewTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l10n.structuredHistoryPatchPreviewBody),
              FilledButton.icon(
                onPressed: _confirming ? null : _apply,
                icon: const Icon(Icons.check),
                label: Text(l10n.structuredHistoryPatchApply),
              ),
            ],
          );
        }
        return StructuredComparisonCard(
          change: changed[previewIndex - 1],
          comparison: preview,
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.structuredHistoryPatchIntro),
        const SizedBox(height: NoWaveSpacing.small),
        Text(l10n.structuredHistoryPatchLimits),
        if (_candidates.isEmpty) Text(l10n.structuredHistoryPatchEmpty),
        Wrap(
          children: [
            TextButton(
              onPressed: _confirming || _candidates.isEmpty
                  ? null
                  : () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(_candidates.map((change) => change.id));
                      _plan = null;
                      _preview = null;
                      _invalid = false;
                    }),
              child: Text(l10n.structuredHistoryPatchSelectAll),
            ),
            TextButton(
              onPressed: _confirming || _selected.isEmpty
                  ? null
                  : () => setState(() {
                      _selected.clear();
                      _plan = null;
                      _preview = null;
                      _invalid = false;
                    }),
              child: Text(l10n.structuredHistoryPatchClear),
            ),
          ],
        ),
        Text('${l10n.structuredHistoryPatchSelected}: ${_selected.length}'),
        OutlinedButton.icon(
          onPressed: _confirming || _selected.isEmpty
              ? null
              : () => setState(_prepare),
          icon: const Icon(Icons.preview),
          label: Text(l10n.structuredHistoryPatchPreview),
        ),
        if (_invalid) Text(l10n.structuredHistoryBlockInvalid),
      ],
    );
  }
}
