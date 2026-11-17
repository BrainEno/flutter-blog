import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One-shot route handoff; the owner clears it even if navigation fails.
class StructuredTransferSeed {
  StructuredTransferSeed(this._capture);
  StructuredTransferCapture? _capture;
  StructuredTransferCapture? take() {
    final capture = _capture;
    _capture = null;
    return capture;
  }

  void clear() => _capture = null;
}

String _encodeBody(StructuredArticleDraft body) =>
    StructuredBodyTransferCodec.encode(body);

/// Explicit clipboard export of a body only. It does not fetch, save, publish,
/// export metadata or include an intermediate text buffer. A pending platform
/// clipboard call cannot be recalled after a session changes.
class StructuredTransferExportPage extends StatefulWidget {
  const StructuredTransferExportPage({
    super.key,
    required this.session,
    required this.seed,
    this.copyText,
  });
  final LocalStructuredSession session;
  final StructuredTransferSeed seed;
  final Future<void> Function(String value)? copyText;

  @override
  State<StructuredTransferExportPage> createState() =>
      _StructuredTransferExportPageState();
}

class _StructuredTransferExportPageState
    extends State<StructuredTransferExportPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredTransferCapture? _capture;
  String? _encoded;
  bool _busy = false;
  bool _copied = false;
  bool _failed = false;
  bool _reading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final capture = widget.seed.take();
    if (capture != null && capture.visibleIn(widget.session)) {
      _capture = capture;
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  void _clear() {
    _generation++;
    _capture = null;
    _encoded = null;
    _copied = false;
    _failed = false;
  }

  void _onState(LocalStructuredState state) {
    final capture = _capture;
    if (capture == null) return;
    if ((state.phase != LocalStructuredPhase.editing &&
            state.phase != LocalStructuredPhase.saveFailed &&
            state.phase != LocalStructuredPhase.conflict) ||
        !identical(state.body, capture.body)) {
      _clear();
    }
    if (mounted && !_reading) setState(() {});
  }

  Future<void> _prepare() async {
    final capture = _capture;
    if (_busy || capture == null || !capture.visibleIn(widget.session)) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _copied = false;
      _encoded = null;
    });
    try {
      // Flutter uses a separate isolate on native platforms. It cannot be
      // cancelled; a late result is discarded after body/account change.
      final encoded = await compute(_encodeBody, capture.body);
      if (!mounted ||
          generation != _generation ||
          _capture == null ||
          !_capture!.visibleIn(widget.session)) {
        return;
      }
      setState(() {
        _encoded = encoded;
        _busy = false;
      });
    } on Object {
      if (!mounted ||
          generation != _generation ||
          _capture == null ||
          !_capture!.visibleIn(widget.session)) {
        return;
      }
      setState(() {
        _failed = true;
        _busy = false;
      });
    }
  }

  Future<void> _copy() async {
    if (_busy || _encoded == null || _capture == null) return;
    final generation = _generation;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredTransferCopyTitle,
      message: l10n.structuredTransferClipboardWarning,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredTransferCopy,
      destructive: false,
    );
    if (!mounted) return;
    final capture = _capture;
    final encoded = _encoded;
    if (!confirmed ||
        generation != _generation ||
        capture == null ||
        encoded == null ||
        !capture.visibleIn(widget.session)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final copy =
          widget.copyText ??
          (String value) => Clipboard.setData(ClipboardData(text: value));
      await copy(encoded);
      if (!mounted ||
          generation != _generation ||
          _capture == null ||
          !_capture!.visibleIn(widget.session)) {
        return;
      }
      setState(() {
        _busy = false;
        _copied = true;
        _failed = false;
      });
    } on Object {
      if (!mounted ||
          generation != _generation ||
          _capture == null ||
          !_capture!.visibleIn(widget.session)) {
        return;
      }
      setState(() {
        _busy = false;
        _failed = true;
        _copied = false;
      });
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
    if (_capture != null && !identical(state.body, _capture!.body)) _clear();
    final l10n = context.l10n;
    final capture = _capture;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredTransferExportTitle)),
      body: SafeArea(
        child: capture == null
            ? Center(child: Text(l10n.structuredTransferStale))
            : ListView(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                children: [
                  Text(l10n.structuredTransferExportIntro),
                  const SizedBox(height: NoWaveSpacing.medium),
                  Text(l10n.structuredTransferExcluded),
                  const SizedBox(height: NoWaveSpacing.small),
                  Text(l10n.structuredTransferClipboardWarning),
                  if (state.hasUnsavedChanges ||
                      state.phase != LocalStructuredPhase.editing)
                    Text(l10n.structuredTransferUnsaved),
                  const SizedBox(height: NoWaveSpacing.medium),
                  Text(
                    '${l10n.structuredTransferVersion}: ${capture.body.version}',
                  ),
                  Text(
                    '${l10n.structuredTransferBlocks}: ${capture.body.blocks.length}',
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _prepare,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(l10n.structuredTransferPrepare),
                  ),
                  if (_busy)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredTransferWorking),
                    ),
                  if (_failed)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredTransferExportFailed),
                    ),
                  if (_encoded != null) ...[
                    Text(
                      '${l10n.structuredTransferUnits}: ${_encoded!.length}',
                    ),
                    Text(l10n.structuredTransferCopyDisclosure),
                    FilledButton.icon(
                      onPressed: _busy ? null : _copy,
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.structuredTransferCopy),
                    ),
                  ],
                  if (_copied)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredTransferCopied),
                    ),
                ],
              ),
      ),
    );
  }
}
