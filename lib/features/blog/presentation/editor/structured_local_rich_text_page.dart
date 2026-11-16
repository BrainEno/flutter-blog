import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_rich_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_run_input.dart';
import 'package:belog/features/blog/domain/editing/structured_rich_text_buffer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Local-only input for one formatted block or selected list item. The editor
/// never constructs a remote update and never flattens other runs. The user
/// explicitly chooses a single run; inserted text retains that run's own
/// attributes. Each accepted intermediate is written through the session CAS.
class StructuredLocalRichTextPage extends StatefulWidget {
  const StructuredLocalRichTextPage({super.key, required this.session});
  final LocalStructuredRichTextSession session;

  @override
  State<StructuredLocalRichTextPage> createState() =>
      _StructuredLocalRichTextPageState();
}

class _StructuredLocalRichTextPageState
    extends State<StructuredLocalRichTextPage>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final StreamSubscription<LocalRichTextState> _subscription;
  StructuredRichTextBuffer? _draft;
  int? _runIndex;
  bool _settingController = false;
  bool _reading = false;
  bool _busy = false;
  bool _exiting = false;
  bool _initialized = false;
  bool _invalid = false;
  bool _recoveredComposition = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onInput);
    _subscription = widget.session.changes.listen(_onSessionChanged);
    unawaited(widget.session.open());
  }

  void _onSessionChanged(LocalRichTextState state) {
    if (state.phase == LocalRichTextPhase.invalidated ||
        state.phase == LocalRichTextPhase.closed) {
      _draft = null;
      _runIndex = null;
      if (_reading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              (widget.session.state.phase == LocalRichTextPhase.invalidated ||
                  widget.session.state.phase == LocalRichTextPhase.closed)) {
            _clearController();
          }
        });
      } else {
        _clearController();
      }
    }
    if (mounted && !_reading) setState(() {});
  }

  void _clearController() {
    _settingController = true;
    try {
      _controller.clear();
      _focus.unfocus();
    } finally {
      _settingController = false;
    }
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
    _controller.removeListener(_onInput);
    unawaited(_subscription.cancel());
    unawaited(widget.session.close());
    _draft = null;
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _resume() {
    final state = widget.session.state;
    final buffer = state.buffer;
    if (state.phase != LocalRichTextPhase.recoveryChoice || buffer == null) {
      return;
    }
    if (!widget.session.resume() ||
        widget.session.state.phase != LocalRichTextPhase.editing) {
      return;
    }
    setState(() {
      _draft = buffer;
      _initialized = true;
      _recoveredComposition = StructuredRichRunInput.hasComposition(buffer);
    });
  }

  bool _canEdit(LocalRichTextState state) =>
      !_busy &&
      !_exiting &&
      !state.finishing &&
      (state.phase == LocalRichTextPhase.editing ||
          state.phase == LocalRichTextPhase.saveFailed ||
          state.phase == LocalRichTextPhase.actionFailed);

  void _chooseRun(int index) {
    final buffer = _draft;
    final state = widget.session.state;
    if (buffer == null ||
        !_canEdit(state) ||
        _recoveredComposition ||
        StructuredRichRunInput.hasComposition(buffer) ||
        !StructuredRichRunInput.canDisplay(buffer, index)) {
      return;
    }
    _focus.unfocus();
    _settingController = true;
    try {
      final text = buffer.runs[index].text;
      // The previous process's IME state is not restorable. Do not install a
      // persisted composing range or a potentially unsafe UTF-16 selection.
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _settingController = false;
    }
    setState(() {
      _runIndex = index;
      _invalid = false;
    });
    _focus.requestFocus();
  }

  TextEditingValue _filter(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = _draft;
    final index = _runIndex;
    if (buffer == null ||
        index == null ||
        !_canEdit(widget.session.state) ||
        _recoveredComposition) {
      return oldValue;
    }
    try {
      StructuredRichRunInput.replace(
        source: buffer,
        index: index,
        text: newValue.text,
        selectionBase: newValue.selection.baseOffset,
        selectionExtent: newValue.selection.extentOffset,
        composingStart: newValue.composing.isValid
            ? newValue.composing.start
            : -1,
        composingEnd: newValue.composing.isValid ? newValue.composing.end : -1,
      );
      return newValue;
    } on FormatException {
      return oldValue;
    } on RangeError {
      return oldValue;
    }
  }

  void _onInput() {
    if (_settingController || _busy || _exiting) return;
    final buffer = _draft;
    final index = _runIndex;
    if (buffer == null || index == null || _recoveredComposition) return;
    try {
      final value = _controller.value;
      final next = StructuredRichRunInput.replace(
        source: buffer,
        index: index,
        text: value.text,
        selectionBase: value.selection.baseOffset,
        selectionExtent: value.selection.extentOffset,
        composingStart: value.composing.isValid ? value.composing.start : -1,
        composingEnd: value.composing.isValid ? value.composing.end : -1,
      );
      if (next.encode() == buffer.encode()) return;
      if (widget.session.edit(next)) {
        final phase = widget.session.state.phase;
        if (phase == LocalRichTextPhase.invalidated ||
            phase == LocalRichTextPhase.closed) {
          return;
        }
        _draft = next;
        if (_invalid && mounted) setState(() => _invalid = false);
      }
    } on FormatException {
      // InputFormatter rejects unrenderable or oversized values before they
      // reach the field; the coordinator validates independently as well.
    } on RangeError {
      // A stale selection cannot be reinterpreted as a different run.
    }
  }

  Future<void> _clearRecoveredComposition() async {
    final current = _draft;
    if (current == null || !_recoveredComposition || _busy) return;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredRichCompositionTitle,
      message: l10n.structuredRichCompositionBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredRichCompositionClear,
    );
    if (!mounted ||
        !confirmed ||
        !identical(_draft, current) ||
        !_canEdit(widget.session.state)) {
      return;
    }
    final next = StructuredRichRunInput.clearComposition(current);
    if (widget.session.edit(next) &&
        widget.session.state.phase != LocalRichTextPhase.invalidated &&
        widget.session.state.phase != LocalRichTextPhase.closed) {
      setState(() {
        _draft = next;
        _recoveredComposition = false;
      });
    }
  }

  Future<void> _leave() async {
    if (_busy || _exiting) return;
    _exiting = true;
    final closed = await widget.session.close();
    if (!mounted) return;
    if (!closed) {
      final l10n = context.l10n;
      final confirmed = await showNoWaveConfirmDialog(
        context,
        title: l10n.structuredExitTitle,
        message: l10n.structuredExitBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.structuredExitAction,
      );
      if (!mounted) return;
      if (!confirmed) {
        _exiting = false;
        return;
      }
      final abandoned = await widget.session.close(abandonUnsaved: true);
      if (!mounted) return;
      if (!abandoned) {
        _exiting = false;
        return;
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _finish({required bool apply}) async {
    if (_busy || _exiting) return;
    _focus.unfocus();
    setState(() => _busy = true);
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: apply
          ? l10n.structuredTextApplyTitle
          : l10n.structuredTextDiscardTitle,
      message: apply
          ? l10n.structuredRichApplyBody
          : l10n.structuredTextDiscardBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: apply
          ? l10n.structuredTextApply
          : l10n.structuredTextDiscard,
      destructive: !apply,
    );
    if (!mounted) return;
    final phase = widget.session.state.phase;
    if (!confirmed ||
        (phase != LocalRichTextPhase.editing &&
            phase != LocalRichTextPhase.actionFailed)) {
      setState(() => _busy = false);
      return;
    }
    final result = apply
        ? await widget.session.apply(confirmed: true)
        : await widget.session.discard(confirmed: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _invalid = result == LocalRichTextFinishResult.invalid;
    });
    if (result == LocalRichTextFinishResult.finished) await _leave();
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final LocalRichTextState state;
    try {
      state = widget.session.state;
    } finally {
      _reading = false;
    }
    final l10n = context.l10n;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
          title: Text(l10n.structuredRichTitle),
        ),
        body: SafeArea(child: _body(context, state)),
      ),
    );
  }

  Widget _body(BuildContext context, LocalRichTextState state) {
    final l10n = context.l10n;
    if (state.phase == LocalRichTextPhase.initial ||
        state.phase == LocalRichTextPhase.opening) {
      return Center(
        child: Semantics(liveRegion: true, child: Text(l10n.structuredLoading)),
      );
    }
    if (state.phase == LocalRichTextPhase.invalidated ||
        state.phase == LocalRichTextPhase.closed) {
      return Center(child: Text(l10n.structuredSessionChanged));
    }
    if (state.phase == LocalRichTextPhase.loadFailed) {
      return Center(child: Text(l10n.structuredLocalFailure));
    }
    if (state.phase == LocalRichTextPhase.conflict && !_initialized) {
      return Center(child: Text(l10n.structuredConflict));
    }
    if (state.phase == LocalRichTextPhase.cancelled) {
      return Center(child: Text(l10n.structuredRecoveryBody));
    }
    if (state.phase == LocalRichTextPhase.recoveryChoice) {
      return ListView(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        children: [
          Text(l10n.structuredRichIntro),
          Text(
            '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
          ),
          const SizedBox(height: NoWaveSpacing.medium),
          Text(
            l10n.structuredRecoveryTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            state.bufferAvailable
                ? l10n.structuredRichRecoverChoice
                : l10n.structuredRichNewChoice,
          ),
          FilledButton(
            onPressed: _resume,
            child: Text(l10n.structuredTextResume),
          ),
          TextButton(
            onPressed: () {
              widget.session.cancel();
              unawaited(_leave());
            },
            child: Text(l10n.actionCancel),
          ),
        ],
      );
    }
    final buffer = _draft;
    if (!_initialized || buffer == null) {
      return Center(child: Text(l10n.structuredLocalFailure));
    }
    final canEdit = _canEdit(state);
    final canFinish =
        !_busy &&
        !state.finishing &&
        (state.phase == LocalRichTextPhase.editing ||
            state.phase == LocalRichTextPhase.actionFailed);
    return ListView(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      children: [
        Text(l10n.structuredRichIntro),
        Text(l10n.structuredRichRunExplanation),
        Text(
          '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
        ),
        if (buffer.itemIndex != null)
          Text('${l10n.structuredInlineListSelected} ${buffer.itemIndex! + 1}'),
        const SizedBox(height: NoWaveSpacing.medium),
        if (_recoveredComposition) ...[
          Semantics(
            liveRegion: true,
            child: Text(l10n.structuredRichCompositionWarning),
          ),
          TextButton(
            onPressed: canEdit ? _clearRecoveredComposition : null,
            child: Text(l10n.structuredRichCompositionClear),
          ),
        ],
        for (var i = 0; i < buffer.runs.length; i++)
          _runCard(context, buffer, i, canEdit),
        if (_runIndex != null && !_recoveredComposition) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          TextField(
            controller: _controller,
            focusNode: _focus,
            readOnly: !canEdit,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            inputFormatters: [TextInputFormatter.withFunction(_filter)],
            decoration: InputDecoration(
              labelText: l10n.structuredRichInput,
              helperText: l10n.structuredRichInputHint,
              errorText: _invalid ? l10n.structuredRichInvalid : null,
            ),
          ),
        ],
        const SizedBox(height: NoWaveSpacing.small),
        Semantics(liveRegion: true, child: Text(_status(context, state))),
        if (state.phase == LocalRichTextPhase.saveFailed)
          TextButton(
            onPressed: _busy ? null : () => widget.session.retrySave(),
            child: Text(l10n.actionRetry),
          ),
        const SizedBox(height: NoWaveSpacing.medium),
        FilledButton(
          onPressed: canFinish ? () => _finish(apply: true) : null,
          child: Text(l10n.structuredTextApply),
        ),
        OutlinedButton(
          onPressed: canFinish ? () => _finish(apply: false) : null,
          child: Text(l10n.structuredTextDiscard),
        ),
      ],
    );
  }

  Widget _runCard(
    BuildContext context,
    StructuredRichTextBuffer buffer,
    int index,
    bool canEdit,
  ) {
    final l10n = context.l10n;
    final run = buffer.runs[index];
    final safe = StructuredRichRunInput.canDisplay(buffer, index);
    final selected = _runIndex == index;
    return Card(
      child: ListTile(
        key: ValueKey('structured-rich-run-$index'),
        title: Text('${l10n.structuredInlineRun} ${index + 1}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              safe
                  ? (run.text.isEmpty ? l10n.structuredRichEmpty : run.text)
                  : l10n.structuredInlineUnsupported,
            ),
            Text(_attributes(context, run)),
            if (selected) Text(l10n.structuredRichSelected),
          ],
        ),
        enabled:
            canEdit &&
            safe &&
            !_recoveredComposition &&
            !StructuredRichRunInput.hasComposition(buffer),
        onTap:
            canEdit &&
                safe &&
                !_recoveredComposition &&
                !StructuredRichRunInput.hasComposition(buffer)
            ? () => _chooseRun(index)
            : null,
      ),
    );
  }

  String _attributes(BuildContext context, StructuredRichBufferRun run) {
    final l10n = context.l10n;
    final labels = <String>[];
    for (final mark in run.marks ?? const <String>[]) {
      labels.add(switch (mark) {
        'bold' => l10n.structuredInlineBold,
        'italic' => l10n.structuredInlineItalic,
        'underline' => l10n.structuredInlineUnderline,
        'strikethrough' => l10n.structuredInlineStrike,
        'code' => l10n.structuredInlineCode,
        _ => mark,
      });
    }
    if (run.href != null) labels.add(l10n.structuredRichHasLink);
    return labels.isEmpty ? l10n.structuredRichPlain : labels.join(' · ');
  }

  String _status(BuildContext context, LocalRichTextState state) {
    final l10n = context.l10n;
    if (state.phase == LocalRichTextPhase.saveFailed) {
      return l10n.structuredSaveFailure;
    }
    if (state.phase == LocalRichTextPhase.conflict) {
      return l10n.structuredConflict;
    }
    if (state.phase == LocalRichTextPhase.actionFailed) {
      return l10n.structuredTextActionFailed;
    }
    if (state.saving || state.hasUnsavedChanges || state.finishing) {
      return l10n.structuredSaving;
    }
    return state.bufferAvailable
        ? l10n.structuredTextKept
        : l10n.structuredNotSaved;
  }
}
