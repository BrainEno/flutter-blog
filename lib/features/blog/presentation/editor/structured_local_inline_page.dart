import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/article_resource_url.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_inline_selection.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_range_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_rich_text_page.dart';
import 'package:belog/features/blog/domain/repositories/structured_rich_text_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'structured_local_inline_runs.dart';

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
  bool _handingOff = false;
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

  void _openRange(StructuredArticleDraft body, int? itemIndex) {
    if (!mounted) return;
    final state = widget.session.state;
    if (state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, body) ||
        (itemIndex != null &&
            (_selectedItem != itemIndex || !identical(_selectedBody, body)))) {
      if (mounted) setState(() => _unsupported = true);
      return;
    }
    final seed = StructuredRangeSeed(widget.session, body);
    try {
      unawaited(
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StructuredLocalRangePage(
                  session: widget.session,
                  blockId: widget.blockId,
                  itemIndex: itemIndex,
                  seed: seed,
                ),
              ),
            )
            .whenComplete(seed.clear),
      );
    } catch (_) {
      seed.clear();
      rethrow;
    }
  }

  Future<void> _openRichText(
    StructuredArticleDraft body,
    int? itemIndex,
  ) async {
    if (_handingOff ||
        widget.session.store is! StructuredRichTextSessionStore) {
      return;
    }
    final state = widget.session.state;
    if (state.phase != LocalStructuredPhase.editing ||
        !identical(state.body, body) ||
        (itemIndex != null &&
            (_selectedItem != itemIndex || !identical(_selectedBody, body)))) {
      return;
    }
    setState(() => _handingOff = true);
    final result = await widget.session.handoffRichText(
      blockId: widget.blockId,
      itemIndex: itemIndex,
      selectedBody: body,
    );
    if (!mounted) {
      await result.session?.close();
      return;
    }
    final session = result.session;
    if (result.status != LocalTextHandoffStatus.ready || session == null) {
      setState(() {
        _handingOff = false;
        _unsupported = true;
      });
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StructuredLocalRichTextPage(session: session),
      ),
    );
    if (mounted) Navigator.of(context).pop();
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
    return PopScope<Object?>(
      canPop: !_handingOff,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_handingOff,
          title: Text(l10n.structuredInlineTitle),
        ),
        body: SafeArea(
          child: !privateState
              ? Center(child: Text(l10n.structuredSessionChanged))
              : body == null || block == null || body.version != 1
              ? Center(child: Text(l10n.structuredInlineUnsupported))
              : _content(context, state, body, block),
        ),
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
    final editable =
        state.phase == LocalStructuredPhase.editing && !_handingOff;
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: runs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.structuredInlineIntro),
              if ((itemIndex == null && block.containsKey('inlines')) ||
                  (itemIndex != null && block.containsKey('itemInlines')))
                OutlinedButton(
                  onPressed:
                      editable &&
                          !_handingOff &&
                          widget.session.store is StructuredRichTextSessionStore
                      ? () => _openRichText(body, itemIndex)
                      : null,
                  child: Text(l10n.structuredRichOpen),
                ),
              OutlinedButton(
                onPressed: editable && !_handingOff
                    ? () => _openRange(body, itemIndex)
                    : null,
                child: Text(l10n.structuredInlineRangeOpen),
              ),
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
    final editable =
        state.phase == LocalStructuredPhase.editing && !_handingOff;
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
