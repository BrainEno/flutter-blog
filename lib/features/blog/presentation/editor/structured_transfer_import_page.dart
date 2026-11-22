import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer_codec.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_card.dart';
import 'package:belog/features/blog/presentation/editor/structured_transfer_export_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_transfer_selection_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

StructuredArticleDraft _decodeBody(String text) =>
    StructuredBodyTransferCodec.decode(text);

enum _ReadFailure { empty, clipboard, invalid }

/// Explicit clipboard read and validated, read-only preview before a local
/// body replacement. No clipboard access is made in initState or build.
class StructuredTransferImportPage extends StatefulWidget {
  const StructuredTransferImportPage({
    super.key,
    required this.session,
    required this.seed,
    this.readText,
  });
  final LocalStructuredSession session;
  final StructuredTransferSeed seed;
  final Future<String?> Function()? readText;

  @override
  State<StructuredTransferImportPage> createState() =>
      _StructuredTransferImportPageState();
}

class _StructuredTransferImportPageState
    extends State<StructuredTransferImportPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredTransferCapture? _capture;
  StructuredTransferPreview? _preview;
  _ReadFailure? _failure;
  bool _busy = false;
  bool _reading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final capture = widget.seed.take();
    if (capture != null && capture.importableIn(widget.session)) {
      _capture = capture;
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  void _clear() {
    _generation++;
    _capture = null;
    _preview = null;
    _failure = null;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onState(LocalStructuredState state) {
    final capture = _capture;
    if (capture == null) return;
    if (state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, capture.body)) {
      _clear();
    }
    if (mounted && !_reading) setState(() {});
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _capture != null &&
      _capture!.importableIn(widget.session);

  Future<void> _readClipboard() async {
    if (_busy || _capture == null || !_capture!.importableIn(widget.session)) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _preview = null;
      _failure = null;
    });
    final String? text;
    try {
      final read =
          widget.readText ??
          () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      text = await read();
    } on Object {
      if (_current(generation)) {
        setState(() {
          _busy = false;
          _failure = _ReadFailure.clipboard;
        });
      }
      return;
    }
    if (!_current(generation)) return;
    if (text == null || text.isEmpty) {
      setState(() {
        _busy = false;
        _failure = _ReadFailure.empty;
      });
      return;
    }
    if (text.length > StructuredBodyTransferCodec.maxEncodedLength) {
      setState(() {
        _busy = false;
        _failure = _ReadFailure.invalid;
      });
      return;
    }
    try {
      // The worker has no credentials or network. It may outlive the route;
      // results are ignored after session/body changes or a newer request.
      final imported = await compute(_decodeBody, text);
      if (!_current(generation)) return;
      final preview = StructuredTransferPreview.create(
        session: widget.session,
        capture: _capture!,
        imported: imported,
      );
      if (!_current(generation)) return;
      if (preview == null) {
        setState(_clear);
        return;
      }
      setState(() {
        _busy = false;
        _preview = preview;
      });
    } on Object {
      if (_current(generation)) {
        setState(() {
          _busy = false;
          _failure = _ReadFailure.invalid;
        });
      }
    }
  }

  Future<void> _apply() async {
    if (_busy || _preview == null || !_preview!.comparison.hasChanges) return;
    final generation = _generation;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredTransferApplyTitle,
      message: l10n.structuredTransferApplyBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredTransferApply,
    );
    if (!mounted) return;
    if (!confirmed) {
      if (_current(generation)) setState(() => _busy = false);
      return;
    }
    if (!_current(generation) || _preview == null) return;
    final result = _preview!.apply(widget.session);
    if (!mounted) return;
    switch (result) {
      case StructuredTransferApplyResult.accepted:
        Navigator.of(context).pop();
      case StructuredTransferApplyResult.unchanged:
        setState(() => _busy = false);
      case StructuredTransferApplyResult.stale:
        setState(_clear);
      case StructuredTransferApplyResult.invalid:
        setState(() {
          _busy = false;
          _failure = _ReadFailure.invalid;
        });
    }
  }

  Future<void> _selectBlocks() async {
    final preview = _preview;
    if (_busy ||
        preview == null ||
        !preview.capture.importableIn(widget.session)) {
      return;
    }
    final seed = StructuredTransferSelectionSeed(preview);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => StructuredTransferSelectionPage(
            session: widget.session,
            seed: seed,
          ),
        ),
      );
    } finally {
      seed.clear();
    }
  }

  @override
  void dispose() {
    widget.seed.clear();
    _clear();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  String _failureText(BuildContext context, _ReadFailure failure) =>
      switch (failure) {
        _ReadFailure.empty => context.l10n.structuredTransferEmpty,
        _ReadFailure.clipboard => context.l10n.structuredTransferReadFailed,
        _ReadFailure.invalid => context.l10n.structuredTransferInvalid,
      };

  @override
  Widget build(BuildContext context) {
    _reading = true;
    try {
      if (_capture != null && !_capture!.importableIn(widget.session)) _clear();
    } finally {
      _reading = false;
    }
    final l10n = context.l10n;
    final preview = _preview;
    final capture = _capture;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredTransferImportTitle)),
      body: SafeArea(
        child: capture == null
            ? Center(child: Text(l10n.structuredTransferStale))
            : _content(context, preview),
      ),
    );
  }

  Widget _content(BuildContext context, StructuredTransferPreview? preview) {
    final l10n = context.l10n;
    final changes =
        preview?.comparison.entries
            .where((entry) => entry.changed)
            .toList(growable: false) ??
        const [];
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: 1 + changes.length,
      itemBuilder: (context, index) {
        if (index > 0 && preview != null) {
          return StructuredComparisonCard(
            key: ValueKey(changes[index - 1].id),
            change: changes[index - 1],
            comparison: preview.comparison,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.structuredTransferImportIntro),
            const SizedBox(height: NoWaveSpacing.small),
            Text(l10n.structuredTransferOriginWarning),
            Text(l10n.structuredTransferExcluded),
            const SizedBox(height: NoWaveSpacing.medium),
            OutlinedButton.icon(
              onPressed: _busy ? null : _readClipboard,
              icon: const Icon(Icons.content_paste),
              label: Text(l10n.structuredTransferRead),
            ),
            if (_busy)
              Semantics(
                liveRegion: true,
                child: Text(l10n.structuredTransferWorking),
              ),
            if (_failure case final failure?)
              Semantics(
                liveRegion: true,
                child: Text(_failureText(context, failure)),
              ),
            if (preview != null) ...[
              const SizedBox(height: NoWaveSpacing.medium),
              Text(
                l10n.structuredTransferPreviewTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l10n.structuredTransferPreviewDirection),
              Text(
                '${l10n.structuredCompareBefore}: ${preview.comparison.before.version} · ${l10n.structuredCompareAfter}: ${preview.comparison.after.version}',
              ),
              if (preview.comparison.versionChanged)
                Text(l10n.structuredCompareVersionChanged),
              Text(
                '${l10n.structuredCompareAdded}: ${preview.comparison.addedCount} · ${l10n.structuredCompareRemoved}: ${preview.comparison.removedCount} · ${l10n.structuredCompareModified}: ${preview.comparison.modifiedCount} · ${l10n.structuredCompareMoved}: ${preview.comparison.movedCount}',
              ),
              Text(l10n.structuredCompareCountsNote),
              if (!preview.comparison.hasChanges)
                Text(l10n.structuredTransferUnchanged),
              const SizedBox(height: NoWaveSpacing.medium),
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        !preview.comparison.entries.any(
                          (entry) => entry.modified,
                        )
                    ? null
                    : _selectBlocks,
                icon: const Icon(Icons.checklist),
                label: Text(l10n.structuredTransferSelectedTitle),
              ),
              FilledButton.icon(
                onPressed: _busy || !preview.comparison.hasChanges
                    ? null
                    : _apply,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(l10n.structuredTransferApply),
              ),
            ],
          ],
        );
      },
    );
  }
}
