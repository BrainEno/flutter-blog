import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One-shot handoff that does not retain a private snapshot in a route closure.
class StructuredRangeSeed {
  StructuredRangeSeed(this.body);
  StructuredArticleDraft? body;
  void clear() => body = null;
}

/// A read-only selection surface. This route cannot insert text or publish.
/// Its snapshot is invalidated on every body replacement, even an ABA change.
class StructuredLocalRangePage extends StatefulWidget {
  const StructuredLocalRangePage({
    super.key,
    required this.session,
    required this.blockId,
    required this.itemIndex,
    required this.seed,
  });

  final LocalStructuredSession session;
  final String blockId;
  final int? itemIndex;
  final StructuredRangeSeed seed;

  @override
  State<StructuredLocalRangePage> createState() =>
      _StructuredLocalRangePageState();
}

class _StructuredLocalRangePageState extends State<StructuredLocalRangePage>
    with WidgetsBindingObserver {
  late final StreamSubscription<LocalStructuredState> _subscription;
  late final TextEditingController _text;
  StructuredArticleDraft? _body;
  String _mark = 'bold';
  bool _reading = false;
  bool _clearing = false;
  bool _invalid = false;
  bool _noChange = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = widget.session.state;
    final body = widget.seed.body;
    widget.seed.clear();
    String? text;
    if (state.phase == LocalStructuredPhase.editing &&
        body != null &&
        identical(state.body, body) &&
        body.version == 1) {
      text = _targetText(body, widget.blockId, widget.itemIndex);
    }
    if (text != null && isWellFormedUtf16(text)) _body = body;
    _text = TextEditingController(text: _body == null ? '' : text);
    _text.addListener(_selectionChanged);
    _subscription = widget.session.changes.listen(_changed);
  }

  void _selectionChanged() {
    if (_clearing || !mounted) return;
    setState(() {
      _invalid = false;
      _noChange = false;
    });
  }

  void _changed(LocalStructuredState state) {
    if (_body != null && !identical(_body, state.body)) {
      _body = null;
      if (_reading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _clearText();
        });
      } else {
        _clearText();
      }
    }
    if (mounted && !_reading) setState(() {});
  }

  void _clearText() {
    _clearing = true;
    _text.clear();
    _clearing = false;
    FocusManager.instance.primaryFocus?.unfocus();
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
    _body = null;
    _text.removeListener(_selectionChanged);
    _text.dispose();
    super.dispose();
  }

  StructuredInlineSelection _selection() {
    if (!mounted) throw StateError('Range route is closed');
    final state = widget.session.state;
    final body = _body;
    if (body == null ||
        state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, body)) {
      throw StateError('Range snapshot changed');
    }
    if (_targetText(body, widget.blockId, widget.itemIndex) != _text.text) {
      throw StateError('Displayed text changed');
    }
    final selection = _text.selection;
    if (!selection.isValid || selection.isCollapsed) {
      throw const FormatException('Select a nonempty range');
    }
    final item = widget.itemIndex;
    if (item == null) {
      return StructuredInlineSelection.textBlock(
        document: body,
        blockId: widget.blockId,
        start: selection.start,
        end: selection.end,
      );
    }
    return StructuredInlineSelection.listItem(
      document: body,
      blockId: widget.blockId,
      itemIndex: item,
      start: selection.start,
      end: selection.end,
    );
  }

  void _apply(
    StructuredArticleDraft Function(
      StructuredInlineSelection,
      StructuredArticleDraft,
    )
    operation,
  ) {
    try {
      final selection = _selection();
      final body = _body!;
      final next = operation(selection, body);
      if (identical(next, body)) {
        setState(() {
          _invalid = false;
          _noChange = true;
        });
        return;
      }
      final applied = widget.session.edit((current) {
        if (!identical(current, body)) {
          throw StateError('Range snapshot changed');
        }
        return operation(selection, current);
      });
      if (!applied && mounted) setState(() => _invalid = true);
    } on ArgumentError {
      if (mounted) setState(() => _invalid = true);
    } on FormatException {
      if (mounted) setState(() => _invalid = true);
    } on StateError {
      if (mounted) setState(() => _invalid = true);
    }
  }

  Future<void> _link() async {
    try {
      final selection = _selection();
      final seed = _RangeLinkSeed(selection, _body!);
      try {
        await showDialog<void>(
          context: context,
          builder: (_) => _RangeLinkDialog(session: widget.session, seed: seed),
        );
      } finally {
        seed.clear();
      }
    } on ArgumentError {
      if (mounted) setState(() => _invalid = true);
    } on FormatException {
      if (mounted) setState(() => _invalid = true);
    } on StateError {
      if (mounted) setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final state = widget.session.state;
    _reading = false;
    final l10n = context.l10n;
    final active = _body != null && identical(_body, state.body);
    final editable = active && state.phase == LocalStructuredPhase.editing;
    final selection = _text.selection;
    final selected = selection.isValid && !selection.isCollapsed;
    final marks = <(String, String)>[
      ('bold', l10n.structuredInlineBold),
      ('italic', l10n.structuredInlineItalic),
      ('underline', l10n.structuredInlineUnderline),
      ('strikethrough', l10n.structuredInlineStrike),
      ('code', l10n.structuredInlineCode),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredRangeTitle)),
      body: SafeArea(
        child: !active
            ? Center(
                child: Text(
                  state.phase == LocalStructuredPhase.invalidated ||
                          state.phase == LocalStructuredPhase.closed
                      ? l10n.structuredSessionChanged
                      : l10n.structuredRangeStale,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                children: [
                  Text(l10n.structuredRangeIntro),
                  const SizedBox(height: NoWaveSpacing.medium),
                  TextField(
                    key: const ValueKey('structured-range-text'),
                    controller: _text,
                    readOnly: true,
                    minLines: 2,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: l10n.structuredRangeText,
                    ),
                  ),
                  const SizedBox(height: NoWaveSpacing.small),
                  if (!selected) Text(l10n.structuredRangeChoose),
                  Text(l10n.structuredRangeStyle),
                  Wrap(
                    spacing: NoWaveSpacing.small,
                    children: [
                      for (final mark in marks)
                        ChoiceChip(
                          label: Text(mark.$2),
                          selected: _mark == mark.$1,
                          onSelected: editable
                              ? (_) => setState(() => _mark = mark.$1)
                              : null,
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: NoWaveSpacing.small,
                    children: [
                      OutlinedButton(
                        onPressed: editable && selected
                            ? () => _apply(
                                (s, b) => s.setMark(b, _mark, enabled: true),
                              )
                            : null,
                        child: Text(l10n.structuredRangeAdd),
                      ),
                      OutlinedButton(
                        onPressed: editable && selected
                            ? () => _apply(
                                (s, b) => s.setMark(b, _mark, enabled: false),
                              )
                            : null,
                        child: Text(l10n.structuredRangeRemove),
                      ),
                      OutlinedButton(
                        onPressed: editable && selected ? _link : null,
                        child: Text(l10n.structuredRangeLink),
                      ),
                      OutlinedButton(
                        onPressed: editable && selected
                            ? () => _apply((s, b) => s.setLink(b, null))
                            : null,
                        child: Text(l10n.structuredRangeRemoveLink),
                      ),
                    ],
                  ),
                  if (_invalid)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredRangeInvalid),
                    ),
                  if (_noChange)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.structuredRangeNoChange),
                    ),
                  if (state.phase == LocalStructuredPhase.saveFailed)
                    Text(l10n.structuredSaveFailure),
                  if (state.phase == LocalStructuredPhase.conflict)
                    Text(l10n.structuredConflict),
                ],
              ),
      ),
    );
  }
}

String? _targetText(StructuredArticleDraft body, String id, int? itemIndex) {
  for (final block in body.blocks) {
    if (block['id'] != id) continue;
    if (itemIndex == null &&
        const {'paragraph', 'heading', 'quote'}.contains(block['type'])) {
      return block['text'] as String;
    }
    if (itemIndex != null && block['type'] == 'list') {
      final items = block['items'] as List;
      if (itemIndex >= 0 && itemIndex < items.length) {
        return items[itemIndex] as String;
      }
    }
    return null;
  }
  return null;
}

class _RangeLinkSeed {
  _RangeLinkSeed(this.selection, this.body);
  StructuredInlineSelection? selection;
  StructuredArticleDraft? body;
  void clear() {
    selection = null;
    body = null;
  }
}

class _RangeLinkDialog extends StatefulWidget {
  const _RangeLinkDialog({required this.session, required this.seed});
  final LocalStructuredSession session;
  final _RangeLinkSeed seed;
  @override
  State<_RangeLinkDialog> createState() => _RangeLinkDialogState();
}

class _RangeLinkDialogState extends State<_RangeLinkDialog> {
  final _controller = TextEditingController();
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredInlineSelection? _selection;
  StructuredArticleDraft? _body;
  bool _invalid = false;
  bool _operationInvalid = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    final state = widget.session.state;
    if (state.phase == LocalStructuredPhase.editing &&
        identical(state.body, widget.seed.body)) {
      _selection = widget.seed.selection;
      _body = widget.seed.body;
    }
    widget.seed.clear();
    _subscription = widget.session.changes.listen((state) {
      if (_body != null && !identical(_body, state.body)) {
        _body = null;
        _selection = null;
        if (_reading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _controller.clear();
          });
        } else {
          _controller.clear();
          FocusManager.instance.primaryFocus?.unfocus();
        }
      }
      if (mounted && !_reading) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _selection = null;
    _body = null;
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    if (!mounted) return;
    final state = widget.session.state;
    final body = _body;
    final selection = _selection;
    if (body == null ||
        selection == null ||
        state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, body)) {
      return;
    }
    final href = _controller.text;
    if (!isValidArticleResourceUrl(href)) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final next = selection.setLink(body, href);
      if (identical(next, body)) {
        Navigator.of(context).pop();
        return;
      }
      final applied = widget.session.edit((current) {
        if (!identical(current, body)) {
          throw StateError('Range snapshot changed');
        }
        return selection.setLink(current, href);
      });
      if (applied && mounted) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _operationInvalid = true);
      }
    } on ArgumentError {
      setState(() => _operationInvalid = true);
    } on FormatException {
      setState(() => _operationInvalid = true);
    } on StateError {
      setState(() => _operationInvalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final state = widget.session.state;
    _reading = false;
    final l10n = context.l10n;
    final privateState =
        state.phase != LocalStructuredPhase.invalidated &&
        state.phase != LocalStructuredPhase.closed;
    final editable =
        _selection != null &&
        _body != null &&
        identical(_body, state.body) &&
        state.phase == LocalStructuredPhase.editing;
    return AlertDialog(
      title: Text(l10n.structuredRangeLinkTitle),
      content: privateState
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.structuredInlineLinkHint),
                  Text(l10n.structuredInlineUnsavedLink),
                  TextField(
                    controller: _controller,
                    enabled: editable,
                    keyboardType: TextInputType.url,
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) =>
                            newValue.text.length <= 2048 ? newValue : oldValue,
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.structuredInlineLinkLabel,
                      errorText: _invalid
                          ? l10n.structuredInlineLinkInvalid
                          : null,
                    ),
                    onChanged: (_) {
                      if (_invalid) setState(() => _invalid = false);
                    },
                  ),
                  if (_operationInvalid) Text(l10n.structuredRangeInvalid),
                  if (!editable) Text(l10n.structuredRangeStale),
                ],
              ),
            )
          : Text(l10n.structuredSessionChanged),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        if (privateState)
          FilledButton(
            onPressed: editable ? _apply : null,
            child: Text(l10n.structuredInlineLinkApply),
          ),
      ],
    );
  }
}
