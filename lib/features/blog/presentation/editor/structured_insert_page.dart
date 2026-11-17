import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_block_insertion.dart';
import 'package:belog/features/blog/domain/editing/structured_list_actions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// A one-shot handoff prevents the route builder from retaining the body after
/// the form consumes it. The caller also clears the seed if navigation fails.
class StructuredInsertSeed {
  StructuredInsertSeed(this._body);
  StructuredArticleDraft? _body;
  StructuredArticleDraft? take() {
    final value = _body;
    _body = null;
    return value;
  }

  void clear() => _body = null;
}

/// Temporary, local-only insert form. The parent session owns durability. This
/// page does not save keystrokes or perform network requests. When editing a
/// list, [itemIndex] is the insertion position in the selected body snapshot.
class StructuredInsertPage extends StatefulWidget {
  const StructuredInsertPage({
    super.key,
    required this.session,
    required this.anchorId,
    required this.seed,
    this.itemIndex,
  });
  final LocalStructuredSession session;
  final String anchorId;
  final StructuredInsertSeed seed;
  final int? itemIndex;

  @override
  State<StructuredInsertPage> createState() => _StructuredInsertPageState();
}

class _StructuredInsertPageState extends State<StructuredInsertPage> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _optionalText = TextEditingController();
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredArticleDraft? _source;
  StructuredNewBlockKind _kind = StructuredNewBlockKind.paragraph;
  int _level = 2;
  int _kindRevision = 0;
  bool _ordered = false;
  bool _optional = false;
  bool _dirty = false;
  bool _busy = false;
  bool _invalid = false;
  bool _reading = false;
  bool _clearing = false;

  bool get _isItem => widget.itemIndex != null;

  @override
  void initState() {
    super.initState();
    final body = widget.seed.take();
    final state = widget.session.state;
    if (body != null &&
        identical(state.body, body) &&
        state.phase == LocalStructuredPhase.editing) {
      final matching = body.blocks.where((b) => b['id'] == widget.anchorId);
      if (matching.length == 1 &&
          (!_isItem || matching.single['type'] == 'list')) {
        _source = body;
      }
    }
    _first.addListener(_changed);
    _second.addListener(_changed);
    _optionalText.addListener(_changed);
    _subscription = widget.session.changes.listen(_onSession);
  }

  void _changed() {
    if (_clearing || !mounted) return;
    setState(() {
      _dirty = true;
      _invalid = false;
    });
  }

  void _onSession(LocalStructuredState state) {
    if (state.phase == LocalStructuredPhase.invalidated ||
        state.phase == LocalStructuredPhase.closed) {
      _source = null;
      _clearing = true;
      _first.clear();
      _second.clear();
      _optionalText.clear();
      _clearing = false;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (mounted && !_reading) setState(() {});
  }

  @override
  void dispose() {
    widget.seed.clear();
    _source = null;
    _first.removeListener(_changed);
    _second.removeListener(_changed);
    _optionalText.removeListener(_changed);
    unawaited(_subscription.cancel());
    _first.dispose();
    _second.dispose();
    _optionalText.dispose();
    super.dispose();
  }

  bool _editable(LocalStructuredState state) =>
      !_busy &&
      _source != null &&
      identical(state.body, _source) &&
      state.phase == LocalStructuredPhase.editing;

  bool get _composing => [_first, _second, _optionalText].any((controller) {
    final range = controller.value.composing;
    return range.isValid && !range.isCollapsed;
  });

  void _apply() {
    final body = _source;
    if (body == null || !_editable(widget.session.state)) return;
    if (_composing) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final StructuredArticleDraft Function(StructuredArticleDraft) operation;
      if (_isItem) {
        operation = StructuredListInsert(
          source: body,
          blockId: widget.anchorId,
          index: widget.itemIndex!,
          text: _first.text,
        ).apply;
      } else {
        operation = StructuredBlockInsertion(
          source: body,
          afterBlockId: widget.anchorId,
          newBlockId: const Uuid().v4(),
          kind: _kind,
          text: _first.text,
          secondary: _second.text,
          optionalPresent: _optional,
          optionalText: _optionalText.text,
          headingLevel: _level,
          ordered: _ordered,
        ).apply;
      }
      if (!widget.session.edit(operation)) {
        if (mounted) setState(() => _invalid = true);
        return;
      }
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } on FormatException {
      if (mounted) setState(() => _invalid = true);
    } on ArgumentError {
      if (mounted) setState(() => _invalid = true);
    } on StateError {
      if (mounted) setState(() => _invalid = true);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty && _source != null) {
      setState(() => _busy = true);
      final l10n = context.l10n;
      final discard = await showNoWaveConfirmDialog(
        context,
        title: l10n.structuredPropertiesLeaveTitle,
        message: l10n.structuredPropertiesLeaveBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.structuredPropertiesLeave,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (!discard) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _kindChanged(StructuredNewBlockKind? value) async {
    if (value == null || value == _kind || !_editable(widget.session.state)) {
      return;
    }
    if (_dirty) {
      setState(() {
        _busy = true;
        _kindRevision++;
      });
      final l10n = context.l10n;
      final discard = await showNoWaveConfirmDialog(
        context,
        title: l10n.structuredInsertChangeKindTitle,
        message: l10n.structuredInsertChangeKindBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.structuredInsertChangeKindConfirm,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (!discard || !_editable(widget.session.state)) return;
    }
    setState(() {
      _kind = value;
      _kindRevision++;
      _invalid = false;
      _dirty = false;
      _clearing = true;
      _first.clear();
      _second.clear();
      _optionalText.clear();
      _clearing = false;
      _optional = false;
      _level = 2;
      _ordered = false;
    });
  }

  String _kindLabel(StructuredNewBlockKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      StructuredNewBlockKind.paragraph => l10n.structuredParagraph,
      StructuredNewBlockKind.heading => l10n.structuredHeading,
      StructuredNewBlockKind.quote => l10n.structuredQuote,
      StructuredNewBlockKind.list => l10n.structuredList,
      StructuredNewBlockKind.image => l10n.structuredImage,
      StructuredNewBlockKind.code => l10n.structuredCode,
    };
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
    final enabled = _editable(state);
    final l10n = context.l10n;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isItem
                ? l10n.structuredInsertItemTitle
                : l10n.structuredInsertBlockTitle,
          ),
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
        ),
        body: SafeArea(
          child: _source == null
              ? Center(
                  child: Text(
                    state.phase == LocalStructuredPhase.invalidated ||
                            state.phase == LocalStructuredPhase.closed
                        ? l10n.structuredSessionChanged
                        : l10n.structuredPropertiesStale,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(NoWaveSpacing.page),
                  children: [
                    Text(l10n.structuredInsertIntro),
                    const SizedBox(height: NoWaveSpacing.medium),
                    if (!_isItem)
                      DropdownButtonFormField<StructuredNewBlockKind>(
                        key: ValueKey(_kindRevision),
                        initialValue: _kind,
                        decoration: InputDecoration(
                          labelText: l10n.structuredInsertKind,
                        ),
                        items: [
                          for (final kind in StructuredNewBlockKind.values)
                            DropdownMenuItem(
                              value: kind,
                              child: Text(_kindLabel(kind)),
                            ),
                        ],
                        onChanged: enabled
                            ? (value) => unawaited(_kindChanged(value))
                            : null,
                      ),
                    ..._fields(context, enabled),
                    if (!enabled)
                      Semantics(
                        liveRegion: true,
                        child: Text(l10n.structuredPropertiesStale),
                      ),
                    if (_invalid)
                      Semantics(
                        liveRegion: true,
                        child: Text(l10n.structuredInsertInvalid),
                      ),
                    const SizedBox(height: NoWaveSpacing.medium),
                    FilledButton(
                      onPressed: enabled ? _apply : null,
                      child: Text(l10n.structuredInsertApply),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context, bool enabled) {
    final l10n = context.l10n;
    final String firstLabel;
    if (_isItem || _kind == StructuredNewBlockKind.list) {
      firstLabel = l10n.structuredInsertItemText;
    } else {
      firstLabel = switch (_kind) {
        StructuredNewBlockKind.image => l10n.structuredInsertImageUrl,
        StructuredNewBlockKind.code => l10n.structuredPropertiesLanguage,
        _ => l10n.structuredInsertBlockText,
      };
    }
    final hint = _isItem || _kind == StructuredNewBlockKind.list
        ? l10n.structuredInsertItemLimit
        : switch (_kind) {
            StructuredNewBlockKind.image => l10n.structuredInsertImageHint,
            StructuredNewBlockKind.code => l10n.structuredInsertCodeLimit,
            StructuredNewBlockKind.quote => l10n.structuredInsertQuoteLimit,
            _ => l10n.structuredInsertTextLimit,
          };
    return [
      const SizedBox(height: NoWaveSpacing.medium),
      Text(hint),
      TextField(
        key: const ValueKey('structured-insert-first'),
        controller: _first,
        enabled: enabled,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(labelText: firstLabel),
      ),
      if (!_isItem && _kind == StructuredNewBlockKind.heading) ...[
        const SizedBox(height: NoWaveSpacing.small),
        Text(l10n.structuredPropertiesLevel),
        Wrap(
          spacing: NoWaveSpacing.small,
          children: [
            for (final level in [2, 3, 4])
              ChoiceChip(
                label: Text('$level'),
                selected: _level == level,
                onSelected: enabled
                    ? (_) => setState(() {
                        _level = level;
                        _dirty = true;
                      })
                    : null,
              ),
          ],
        ),
      ],
      if (!_isItem && _kind == StructuredNewBlockKind.list)
        SwitchListTile(
          value: _ordered,
          title: Text(l10n.structuredPropertiesOrdered),
          onChanged: enabled
              ? (value) => setState(() {
                  _ordered = value;
                  _dirty = true;
                })
              : null,
        ),
      if (!_isItem &&
          (_kind == StructuredNewBlockKind.image ||
              _kind == StructuredNewBlockKind.code)) ...[
        const SizedBox(height: NoWaveSpacing.medium),
        TextField(
          key: const ValueKey('structured-insert-second'),
          controller: _second,
          enabled: enabled,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: _kind == StructuredNewBlockKind.image
                ? l10n.structuredPropertiesAlt
                : l10n.structuredPropertiesCode,
          ),
        ),
      ],
      if (!_isItem &&
          (_kind == StructuredNewBlockKind.image ||
              _kind == StructuredNewBlockKind.quote)) ...[
        SwitchListTile(
          value: _optional,
          title: Text(
            _kind == StructuredNewBlockKind.image
                ? l10n.structuredPropertiesCaptionPresent
                : l10n.structuredPropertiesAttributionPresent,
          ),
          onChanged: enabled
              ? (value) => setState(() {
                  _optional = value;
                  _dirty = true;
                })
              : null,
        ),
        if (_optional)
          TextField(
            key: const ValueKey('structured-insert-optional'),
            controller: _optionalText,
            enabled: enabled,
            maxLines: null,
            decoration: InputDecoration(
              labelText: _kind == StructuredNewBlockKind.image
                  ? l10n.structuredPropertiesCaption
                  : l10n.structuredPropertiesAttribution,
            ),
          ),
      ],
    ];
  }
}
