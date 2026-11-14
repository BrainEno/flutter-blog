import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_text_session.dart';
import 'package:belog/features/blog/domain/editing/structured_text_buffer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One local unformatted block, backed by a separately recoverable buffer.
/// It never sends an article or constructs a publication request.
class StructuredLocalTextPage extends StatefulWidget {
  const StructuredLocalTextPage({super.key, required this.session});
  final LocalStructuredTextSession session;

  @override
  State<StructuredLocalTextPage> createState() =>
      _StructuredLocalTextPageState();
}

class _StructuredLocalTextPageState extends State<StructuredLocalTextPage>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  late final StreamSubscription<LocalTextState> _subscription;
  bool _reading = false;
  bool _busy = false;
  bool _exiting = false;
  bool _invalid = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.changes.listen((state) {
      if (state.phase == LocalTextPhase.invalidated ||
          state.phase == LocalTextPhase.closed) {
        if (_reading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                (widget.session.state.phase == LocalTextPhase.invalidated ||
                    widget.session.state.phase == LocalTextPhase.closed)) {
              _controller.clear();
              FocusManager.instance.primaryFocus?.unfocus();
            }
          });
        } else {
          _controller.clear();
          FocusManager.instance.primaryFocus?.unfocus();
        }
      }
      if (mounted && !_reading) setState(() {});
    });
    unawaited(widget.session.open());
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
    unawaited(_subscription.cancel());
    unawaited(widget.session.close());
    _controller.dispose();
    super.dispose();
  }

  void _resume() {
    final state = widget.session.state;
    if (state.phase != LocalTextPhase.recoveryChoice || state.text == null) {
      return;
    }
    // Populate only once, immediately before an explicit resume. A later save
    // acknowledgement must never replace newer controller input or selection.
    _controller.value = TextEditingValue(
      text: state.text!,
      selection: TextSelection.collapsed(offset: state.text!.length),
    );
    if (widget.session.resume()) {
      _initialized = true;
    } else {
      _controller.clear();
    }
  }

  void _changed(String value) {
    try {
      if (widget.session.edit(value)) {
        if (_invalid) setState(() => _invalid = false);
      }
    } on FormatException {
      // The input formatter prevents overlength edits. The domain still
      // validates every change independently; never synthesize a body here.
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
    setState(() => _busy = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: apply
          ? l10n.structuredTextApplyTitle
          : l10n.structuredTextDiscardTitle,
      message: apply
          ? l10n.structuredTextApplyBody
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
        (phase != LocalTextPhase.editing &&
            phase != LocalTextPhase.actionFailed)) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _invalid = false);
    final result = apply
        ? await widget.session.apply(confirmed: true)
        : await widget.session.discard(confirmed: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _invalid = result == LocalTextFinishResult.invalid;
    });
    if (result == LocalTextFinishResult.finished) await _leave();
  }

  bool _acceptsInput() {
    if (_busy || _exiting) return false;
    _reading = true;
    try {
      final state = widget.session.state;
      return !state.finishing &&
          (state.phase == LocalTextPhase.editing ||
              state.phase == LocalTextPhase.saveFailed ||
              state.phase == LocalTextPhase.actionFailed);
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final LocalTextState state;
    try {
      state = widget.session.state;
    } finally {
      _reading = false;
    }
    final l10n = context.l10n;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
          title: Text(l10n.structuredTextTitle),
        ),
        body: SafeArea(child: _content(context, state)),
      ),
    );
  }

  Widget _content(BuildContext context, LocalTextState state) {
    final l10n = context.l10n;
    if (state.phase == LocalTextPhase.initial ||
        state.phase == LocalTextPhase.opening) {
      return Center(
        child: Semantics(liveRegion: true, child: Text(l10n.structuredLoading)),
      );
    }
    if (state.phase == LocalTextPhase.invalidated ||
        state.phase == LocalTextPhase.closed) {
      return Center(child: Text(l10n.structuredSessionChanged));
    }
    if (state.phase == LocalTextPhase.loadFailed) {
      return Center(child: Text(l10n.structuredLocalFailure));
    }
    if (state.phase == LocalTextPhase.conflict && !_initialized) {
      return Center(child: Text(l10n.structuredConflict));
    }
    if (state.phase == LocalTextPhase.cancelled) {
      return Center(child: Text(l10n.structuredRecoveryBody));
    }
    if (state.phase == LocalTextPhase.recoveryChoice) {
      return ListView(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        children: [
          Text(l10n.structuredTextIntro),
          Text(
            '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
          ),
          const SizedBox(height: NoWaveSpacing.medium),
          Text(
            l10n.structuredRecoveryTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(l10n.structuredTextChoice),
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
    if (!_initialized) return Center(child: Text(l10n.structuredLocalFailure));
    final canEdit =
        !_busy &&
        !state.finishing &&
        (state.phase == LocalTextPhase.editing ||
            state.phase == LocalTextPhase.actionFailed ||
            state.phase == LocalTextPhase.saveFailed);
    final canFinish =
        !_busy &&
        !state.finishing &&
        (state.phase == LocalTextPhase.editing ||
            state.phase == LocalTextPhase.actionFailed);
    return ListView(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      children: [
        Text(l10n.structuredTextIntro),
        Text(
          '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
        ),
        Text(l10n.structuredTextReturn),
        const SizedBox(height: NoWaveSpacing.medium),
        TextField(
          controller: _controller,
          readOnly: !canEdit,
          minLines: 4,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          inputFormatters: [
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  _acceptsInput() &&
                      newValue.text.length <= StructuredTextBuffer.maxTextLength
                  ? newValue
                  : oldValue,
            ),
          ],
          decoration: InputDecoration(
            labelText: l10n.structuredTextLabel,
            helperText: l10n.structuredTextLimit,
            errorText: _invalid ? l10n.structuredTextInvalid : null,
          ),
          onChanged: _changed,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        Semantics(liveRegion: true, child: Text(_status(context, state))),
        if (state.phase == LocalTextPhase.saveFailed)
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

  String _status(BuildContext context, LocalTextState state) {
    final l10n = context.l10n;
    if (state.phase == LocalTextPhase.saveFailed) {
      return l10n.structuredSaveFailure;
    }
    if (state.phase == LocalTextPhase.conflict) return l10n.structuredConflict;
    if (state.phase == LocalTextPhase.actionFailed) {
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
