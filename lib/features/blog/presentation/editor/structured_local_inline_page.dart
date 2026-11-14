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

/// Edits whole existing text runs using the owner's local body coordinator.
/// This route never owns or closes the session and never opens a link.
class StructuredLocalInlinePage extends StatefulWidget {
  const StructuredLocalInlinePage({
    super.key,
    required this.session,
    required this.blockId,
  });

  final LocalStructuredSession session;
  final String blockId;

  @override
  State<StructuredLocalInlinePage> createState() =>
      _StructuredLocalInlinePageState();
}

class _StructuredLocalInlinePageState extends State<StructuredLocalInlinePage>
    with WidgetsBindingObserver {
  late final StreamSubscription<LocalStructuredState> _subscription;
  bool _reading = false;
  bool _unsupported = false;
  int? _selectedItem;
  StructuredArticleDraft? _selectedBody;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.changes.listen((state) {
      // List items have no stable IDs. Any new body snapshot invalidates the
      // selection, including our own edit and account invalidation.
      if (_selectedItem != null && !identical(_selectedBody, state.body)) {
        _selectedItem = null;
        _selectedBody = null;
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
    unawaited(_subscription.cancel());
    _selectedItem = null;
    _selectedBody = null;
    super.dispose();
  }

  StructuredInlineSelection _select(StructuredArticleDraft body, _Run run) {
    final item = run.itemIndex;
    if (item == null) {
      return StructuredInlineSelection.textBlock(
        document: body,
        blockId: widget.blockId,
        start: run.start,
        end: run.end,
      );
    }
    final current = widget.session.state;
    if (_selectedItem != item ||
        !identical(_selectedBody, body) ||
        current.phase != LocalStructuredPhase.editing ||
        !identical(current.body, body)) {
      throw StateError('List item selection changed');
    }
    return StructuredInlineSelection.listItem(
      document: body,
      blockId: widget.blockId,
      itemIndex: item,
      start: run.start,
      end: run.end,
    );
  }

  void _chooseItem(StructuredArticleDraft body, int index) {
    final state = widget.session.state;
    if (state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, body)) {
      if (mounted) setState(() => _unsupported = true);
      return;
    }
    setState(() {
      _selectedItem = index;
      _selectedBody = body;
      _unsupported = false;
    });
  }

  void _clearItem() {
    setState(() {
      _selectedItem = null;
      _selectedBody = null;
      _unsupported = false;
    });
  }

  void _mark(StructuredArticleDraft body, _Run run, String mark, bool enabled) {
    try {
      final selection = _select(body, run);
      final applied = widget.session.edit(
        (current) => selection.setMark(current, mark, enabled: enabled),
      );
      if (!applied && mounted) setState(() => _unsupported = true);
    } on ArgumentError {
      if (mounted) setState(() => _unsupported = true);
    } on FormatException {
      if (mounted) setState(() => _unsupported = true);
    } on StateError {
      if (mounted) setState(() => _unsupported = true);
    }
  }

  Future<void> _link(StructuredArticleDraft body, _Run run) async {
    try {
      final selection = _select(body, run);
      // The mutable seed is emptied as soon as the dialog adopts it. It avoids
      // retaining another copy of the selection in the dialog builder closure.
      final seed = _LinkSeed(
        selection,
        run.href,
        run.itemIndex == null ? null : body,
      );
      try {
        await showDialog<void>(
          context: context,
          builder: (_) => _LinkDialog(session: widget.session, seed: seed),
        );
      } finally {
        seed.clear();
      }
    } on ArgumentError {
      if (mounted) setState(() => _unsupported = true);
    } on FormatException {
      if (mounted) setState(() => _unsupported = true);
    } on StateError {
      if (mounted) setState(() => _unsupported = true);
    }
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
    final l10n = context.l10n;
    final body = state.body;
    if (_selectedItem != null && !identical(_selectedBody, body)) {
      _selectedItem = null;
      _selectedBody = null;
    }
    final privateState =
        state.phase != LocalStructuredPhase.invalidated &&
        state.phase != LocalStructuredPhase.closed;
    final block = privateState && body != null
        ? _findSupportedBlock(body, widget.blockId)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredInlineTitle)),
      body: SafeArea(
        child: !privateState
            ? Center(child: Text(l10n.structuredSessionChanged))
            : body == null || block == null || body.version != 1
            ? Center(child: Text(l10n.structuredInlineUnsupported))
            : _content(context, state, body, block),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    LocalStructuredState state,
    StructuredArticleDraft body,
    Map<String, Object?> block,
  ) {
    final l10n = context.l10n;
    final isList = block['type'] == 'list';
    if (isList && _selectedItem == null) {
      return _listItems(context, state, body, block);
    }
    final itemIndex = isList ? _selectedItem : null;
    final runs = _runs(block, itemIndex: itemIndex);
    final editable = state.phase == LocalStructuredPhase.editing;
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: runs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.structuredInlineIntro),
              if (itemIndex != null) ...[
                Text('${l10n.structuredInlineListSelected} ${itemIndex + 1}'),
                TextButton(
                  onPressed: _clearItem,
                  child: Text(l10n.structuredInlineListChoose),
                ),
              ],
              const SizedBox(height: NoWaveSpacing.small),
              Semantics(liveRegion: true, child: Text(_status(context, state))),
              if (state.phase == LocalStructuredPhase.saveFailed)
                TextButton(
                  onPressed: () => widget.session.retrySave(),
                  child: Text(l10n.actionRetry),
                ),
              if (_unsupported)
                Semantics(
                  liveRegion: true,
                  child: Text(l10n.structuredInlineUnsupported),
                ),
              const SizedBox(height: NoWaveSpacing.medium),
            ],
          );
        }
        final run = runs[index - 1];
        return _RunCard(
          key: ValueKey('structured-inline-run-${index - 1}'),
          run: run,
          index: index,
          editable: editable,
          onMark: (mark, enabled) => _mark(body, run, mark, enabled),
          onLink: () => _link(body, run),
        );
      },
    );
  }

  Widget _listItems(
    BuildContext context,
    LocalStructuredState state,
    StructuredArticleDraft body,
    Map<String, Object?> block,
  ) {
    final l10n = context.l10n;
    final items = block['items'] as List;
    final editable = state.phase == LocalStructuredPhase.editing;
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.structuredInlineListIntro),
              const SizedBox(height: NoWaveSpacing.small),
              Semantics(liveRegion: true, child: Text(_status(context, state))),
              if (state.phase == LocalStructuredPhase.saveFailed)
                TextButton(
                  onPressed: () => widget.session.retrySave(),
                  child: Text(l10n.actionRetry),
                ),
              if (_unsupported)
                Semantics(
                  liveRegion: true,
                  child: Text(l10n.structuredInlineUnsupported),
                ),
              const SizedBox(height: NoWaveSpacing.medium),
            ],
          );
        }
        final text = items[index - 1] as String;
        final safe = isWellFormedUtf16(text);
        return Card(
          child: ListTile(
            key: ValueKey('structured-list-item-${index - 1}'),
            title: Text('${l10n.structuredInlineListItem} $index'),
            subtitle: Text(safe ? text : l10n.structuredInlineUnsupported),
            enabled: editable && safe,
            onTap: editable && safe ? () => _chooseItem(body, index - 1) : null,
          ),
        );
      },
    );
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
}

Map<String, Object?>? _findSupportedBlock(
  StructuredArticleDraft body,
  String id,
) {
  for (final block in body.blocks) {
    if (block['id'] == id &&
        const {
          'paragraph',
          'heading',
          'quote',
          'list',
        }.contains(block['type'])) {
      return block;
    }
  }
  return null;
}

class _Run {
  const _Run({
    required this.text,
    required this.start,
    required this.end,
    required this.marks,
    required this.href,
    required this.itemIndex,
  });
  final int? itemIndex;
  final String text;
  final int start;
  final int end;
  final Set<String> marks;
  final String? href;
}

List<_Run> _runs(Map<String, Object?> block, {int? itemIndex}) {
  final List raw;
  if (itemIndex == null) {
    raw =
        block['inlines'] as List? ??
        [
          {'text': block['text']},
        ];
  } else {
    final all = block['itemInlines'] as List?;
    raw = all == null
        ? [
            {'text': (block['items'] as List)[itemIndex]},
          ]
        : all[itemIndex] as List;
  }
  var offset = 0;
  return [
    for (final value in raw)
      (() {
        final run = value as Map;
        final text = run['text'] as String;
        final result = _Run(
          text: text,
          start: offset,
          end: offset + text.length,
          marks: Set<String>.of((run['marks'] as List?)?.cast<String>() ?? []),
          href: run['href'] as String?,
          itemIndex: itemIndex,
        );
        offset += text.length;
        return result;
      })(),
  ];
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    super.key,
    required this.run,
    required this.index,
    required this.editable,
    required this.onMark,
    required this.onLink,
  });
  final _Run run;
  final int index;
  final bool editable;
  final void Function(String, bool) onMark;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safe =
        isWellFormedUtf16(run.text) &&
        (run.href == null || isWellFormedUtf16(run.href!));
    final marks = <(String, String)>[
      ('bold', l10n.structuredInlineBold),
      ('italic', l10n.structuredInlineItalic),
      ('underline', l10n.structuredInlineUnderline),
      ('strikethrough', l10n.structuredInlineStrike),
      ('code', l10n.structuredInlineCode),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.structuredInlineRun} $index'),
            if (safe)
              SelectableText(run.text)
            else
              Text(l10n.structuredInlineUnsupported),
            if (safe && run.href != null) Text(run.href!),
            Wrap(
              spacing: NoWaveSpacing.small,
              children: [
                for (final mark in marks)
                  FilterChip(
                    label: Text(mark.$2),
                    selected: run.marks.contains(mark.$1),
                    onSelected: editable && safe
                        ? (selected) => onMark(mark.$1, selected)
                        : null,
                  ),
              ],
            ),
            OutlinedButton(
              onPressed: editable && safe ? onLink : null,
              child: Text(l10n.structuredInlineLink),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkSeed {
  _LinkSeed(this.selection, this.href, this.listBody);
  StructuredInlineSelection? selection;
  String? href;
  StructuredArticleDraft? listBody;
  void clear() {
    selection = null;
    href = null;
    listBody = null;
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.session, required this.seed});
  final LocalStructuredSession session;
  final _LinkSeed seed;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _controller;
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredInlineSelection? _selection;
  StructuredArticleDraft? _listBody;
  bool _hadLink = false;
  bool _reading = false;
  bool _invalid = false;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    // The route can be scheduled just before an identity change. Check the
    // current fence before adopting private seed values, not only on events.
    final state = widget.session.state;
    final active =
        state.phase == LocalStructuredPhase.editing &&
        (widget.seed.listBody == null ||
            identical(widget.seed.listBody, state.body));
    _listBody = active ? widget.seed.listBody : null;
    _selection = active ? widget.seed.selection : null;
    _hadLink = active && widget.seed.href != null;
    _controller = TextEditingController(
      text: active ? widget.seed.href ?? '' : '',
    );
    widget.seed.clear();
    _subscription = widget.session.changes.listen(_changed);
  }

  void _changed(LocalStructuredState state) {
    if (!mounted) return;
    if (_listBody != null && !identical(_listBody, state.body)) {
      _listBody = null;
      _selection = null;
      _stale = true;
    }
    if (state.phase == LocalStructuredPhase.invalidated ||
        state.phase == LocalStructuredPhase.closed) {
      _selection = null;
      _listBody = null;
      if (_reading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
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
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _selection = null;
    _listBody = null;
    _controller.dispose();
    super.dispose();
  }

  void _apply({required bool remove}) {
    final state = widget.session.state;
    final selection = _selection;
    if (state.phase != LocalStructuredPhase.editing ||
        state.body == null ||
        selection == null ||
        (_listBody != null && !identical(_listBody, state.body))) {
      setState(() => _stale = true);
      return;
    }
    final href = remove ? null : _controller.text;
    if (href != null && !isValidArticleResourceUrl(href)) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final next = selection.setLink(state.body!, href);
      if (identical(next, state.body)) {
        Navigator.of(context).pop();
        return;
      }
      final applied = widget.session.edit(
        (current) => selection.setLink(current, href),
      );
      if (applied) {
        Navigator.of(context).pop();
      } else {
        setState(() => _stale = true);
      }
    } on ArgumentError {
      setState(() => _stale = true);
    } on FormatException {
      setState(() => _stale = true);
    } on StateError {
      setState(() => _stale = true);
    }
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
    final l10n = context.l10n;
    final privateState =
        state.phase != LocalStructuredPhase.invalidated &&
        state.phase != LocalStructuredPhase.closed;
    final editable =
        state.phase == LocalStructuredPhase.editing && _selection != null;
    return AlertDialog(
      title: Text(l10n.structuredInlineLinkTitle),
      content: SingleChildScrollView(
        child: privateState
            ? Column(
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
                  if (_stale || !editable) Text(l10n.structuredInlineStale),
                ],
              )
            : Text(l10n.structuredSessionChanged),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        if (_hadLink && privateState)
          TextButton(
            onPressed: editable ? () => _apply(remove: true) : null,
            child: Text(l10n.structuredInlineLinkRemove),
          ),
        if (privateState)
          FilledButton(
            onPressed: editable ? () => _apply(remove: false) : null,
            child: Text(l10n.structuredInlineLinkApply),
          ),
      ],
    );
  }
}
