import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/domain/editing/structured_history_patch.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_card.dart';
import 'package:flutter/material.dart';

class StructuredTransferSelectionSeed {
  StructuredTransferSelectionSeed(this._preview);
  StructuredTransferPreview? _preview;
  StructuredTransferPreview? take() {
    final preview = _preview;
    _preview = null;
    return preview;
  }

  void clear() => _preview = null;
}

/// A preview-first, selected-block alternative to replacing the whole body.
/// It cannot infer insertion/deletion/ordering and never invokes the server.
class StructuredTransferSelectionPage extends StatefulWidget {
  const StructuredTransferSelectionPage({
    super.key,
    required this.session,
    required this.seed,
  });
  final LocalStructuredSession session;
  final StructuredTransferSelectionSeed seed;

  @override
  State<StructuredTransferSelectionPage> createState() =>
      _StructuredTransferSelectionPageState();
}

class _StructuredTransferSelectionPageState
    extends State<StructuredTransferSelectionPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredTransferPreview? _source;
  List<StructuredBlockChange> _candidates = const [];
  final Set<String> _selected = {};
  StructuredHistoryPatch? _plan;
  StructuredDocumentComparison? _diff;
  bool _invalid = false;
  bool _busy = false;
  bool _reading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final source = widget.seed.take();
    if (source != null && source.capture.importableIn(widget.session)) {
      _source = source;
      _candidates = List.unmodifiable(
        source.comparison.entries.where((entry) => entry.modified),
      );
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  void _clear() {
    _generation++;
    _source = null;
    _candidates = const [];
    _selected.clear();
    _plan = null;
    _diff = null;
    _invalid = false;
  }

  void _onState(LocalStructuredState state) {
    if (_source != null &&
        (state.phase != LocalStructuredPhase.editing ||
            !identical(state.body, _source!.capture.body))) {
      _clear();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted && !_reading) setState(() {});
    }
  }

  void _change(String id, bool value) {
    if (value) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
    _plan = null;
    _diff = null;
    _invalid = false;
    _generation++;
  }

  void _prepare() {
    final source = _source;
    if (source == null ||
        _selected.isEmpty ||
        !source.capture.importableIn(widget.session)) {
      return;
    }
    try {
      final plan = source.prepareSelected(_selected);
      _plan = plan;
      _diff = StructuredDocumentComparison.between(plan.current, plan.result);
      _invalid = false;
    } on FormatException {
      _plan = null;
      _diff = null;
      _invalid = true;
    }
  }

  Future<void> _apply() async {
    if (_busy || _source == null || _plan == null) return;
    final generation = _generation;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredTransferSelectedConfirmTitle,
      message: l10n.structuredTransferSelectedConfirmBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredTransferSelectedApply,
    );
    if (!mounted) return;
    final source = _source;
    final plan = _plan;
    if (!confirmed) {
      setState(() => _busy = false);
      return;
    }
    if (generation != _generation ||
        source == null ||
        plan == null ||
        !source.capture.importableIn(widget.session)) {
      return;
    }
    final result = source.applySelected(widget.session, plan.blockIds);
    if (!mounted) return;
    switch (result) {
      case StructuredTransferApplyResult.accepted:
        Navigator.of(context).pop(true);
      case StructuredTransferApplyResult.invalid:
        setState(() {
          _busy = false;
          _plan = null;
          _diff = null;
          _invalid = true;
        });
      case StructuredTransferApplyResult.stale:
        setState(_clear);
      case StructuredTransferApplyResult.unchanged:
        setState(() => _busy = false);
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
    try {
      if (_source != null && !_source!.capture.importableIn(widget.session)) {
        _clear();
      }
    } finally {
      _reading = false;
    }
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.structuredTransferSelectedTitle)),
      body: SafeArea(
        child: source == null
            ? Center(child: Text(context.l10n.structuredTransferStale))
            : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final diff = _diff;
    final changed =
        diff?.entries.where((entry) => entry.changed).toList(growable: false) ??
        const <StructuredBlockChange>[];
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount:
          1 + _candidates.length + (diff == null ? 0 : 1 + changed.length),
      itemBuilder: (context, index) {
        if (index == 0) return _intro(context);
        if (index <= _candidates.length) {
          final item = _candidates[index - 1];
          final id = isWellFormedUtf16(item.id)
              ? item.id
              : l10n.structuredInlineUnsupported;
          return CheckboxListTile(
            key: ValueKey('transfer-select-${item.id}'),
            value: _selected.contains(item.id),
            onChanged: _busy
                ? null
                : (value) => setState(() => _change(item.id, value == true)),
            title: Text('${l10n.structuredCompareBlockId}: $id'),
            subtitle: Text(
              '${l10n.structuredCompareBeforePosition}: ${item.beforeIndex! + 1}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          );
        }
        if (diff == null) return const SizedBox.shrink();
        final previewIndex = index - _candidates.length - 1;
        if (previewIndex == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: NoWaveSpacing.medium),
              Text(
                l10n.structuredTransferSelectedPreview,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l10n.structuredTransferSelectedDirection),
              FilledButton.icon(
                onPressed: _busy ? null : _apply,
                icon: const Icon(Icons.check),
                label: Text(l10n.structuredTransferSelectedApply),
              ),
            ],
          );
        }
        return StructuredComparisonCard(
          change: changed[previewIndex - 1],
          comparison: diff,
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.structuredTransferSelectedIntro),
        Text(l10n.structuredTransferSelectedLimits),
        if (_candidates.isEmpty) Text(l10n.structuredHistoryPatchEmpty),
        Wrap(
          children: [
            TextButton(
              onPressed: _busy || _candidates.isEmpty
                  ? null
                  : () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(_candidates.map((entry) => entry.id));
                      _plan = null;
                      _diff = null;
                      _invalid = false;
                      _generation++;
                    }),
              child: Text(l10n.structuredHistoryPatchSelectAll),
            ),
            TextButton(
              onPressed: _busy || _selected.isEmpty
                  ? null
                  : () => setState(() {
                      _selected.clear();
                      _plan = null;
                      _diff = null;
                      _invalid = false;
                      _generation++;
                    }),
              child: Text(l10n.structuredHistoryPatchClear),
            ),
          ],
        ),
        Text('${l10n.structuredHistoryPatchSelected}: ${_selected.length}'),
        OutlinedButton.icon(
          onPressed: _busy || _selected.isEmpty
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
