import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_text_session_store.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_text_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_body_history_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_transfer_export_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_transfer_import_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_recovery_review_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_block_properties_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_insert_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_list_page.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_inline_page.dart';
import 'package:flutter/material.dart';

enum _BodyHistoryAction { undo, redo, review, exportBody, importBody }

/// A deliberately limited local-only editor. It never constructs a server
/// request. Plain text uses a separate local session with explicit recovery.
class StructuredLocalEditorPage extends StatefulWidget {
  const StructuredLocalEditorPage({super.key, required this.session});
  final LocalStructuredSession session;

  @override
  State<StructuredLocalEditorPage> createState() =>
      _StructuredLocalEditorPageState();
}

class _StructuredLocalEditorPageState extends State<StructuredLocalEditorPage>
    with WidgetsBindingObserver {
  late StreamSubscription<LocalStructuredState> _subscription;
  bool _readingState = false;
  int? _historyMenuGeneration;
  StructuredArticleDraft? _historyMenuBody;
  bool _busy = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.changes.listen((state) {
      if (!identical(state.body, _historyMenuBody)) {
        _historyMenuBody = null;
        _historyMenuGeneration = null;
      }
      // A getter can discover a missed identity event while build is already
      // reading the new state. In that case this build itself is the update.
      if (mounted && !_readingState) setState(() {});
    });
    unawaited(widget.session.open());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Edits were already admitted to the serialized writer. This is only a
      // best-effort flush; suspension or process termination is not durability.
      unawaited(widget.session.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyMenuBody = null;
    _historyMenuGeneration = null;
    unawaited(_subscription.cancel());
    // Unexpected external route removal cannot silently delete the saved row.
    // A failed in-memory write still requires an explicit user decision.
    unawaited(widget.session.close());
    super.dispose();
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

  Future<void> _discardRecovery() async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredDiscardTitle,
      message: l10n.structuredDiscardBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredRecoveryDiscard,
    );
    if (!mounted ||
        !confirmed ||
        widget.session.state.phase != LocalStructuredPhase.recoveryChoice) {
      return;
    }
    setState(() => _busy = true);
    await widget.session.discardRecovery(confirmed: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(String id) async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.structuredRemoveTitle,
      message: l10n.structuredRemoveBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.structuredRemove,
    );
    if (!mounted || !confirmed) return;
    _edit((body) => body.remove(id));
  }

  StructuredBodyHistorySeed? _historySeed() {
    final view = widget.session.captureBodyHistory();
    return view == null ? null : StructuredBodyHistorySeed(view);
  }

  Future<void> _openHistory() async {
    if (_busy || _exiting) return;
    final seed = _historySeed();
    if (seed == null) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              StructuredBodyHistoryPage(session: widget.session, seed: seed),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  StructuredTransferSeed? _transferSeed() {
    final capture = StructuredTransferCapture.take(widget.session);
    return capture == null ? null : StructuredTransferSeed(capture);
  }

  Future<void> _openTransfer({required bool import}) async {
    if (_busy || _exiting) return;
    final seed = _transferSeed();
    if (seed == null) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => import
              ? StructuredTransferImportPage(
                  session: widget.session,
                  seed: seed,
                )
              : StructuredTransferExportPage(
                  session: widget.session,
                  seed: seed,
                ),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openComparison() async {
    if (_busy || _exiting) return;
    final capture = widget.session.captureComparison();
    if (capture == null) return;
    final seed = StructuredComparisonSeed(capture);
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              StructuredComparisonPage(session: widget.session, seed: seed),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openText(String blockId) async {
    if (_busy || _exiting) return;
    setState(() => _busy = true);
    final result = await widget.session.handoffPlainText(blockId);
    if (!mounted) {
      await result.session?.close();
      return;
    }
    final text = result.session;
    if (result.status != LocalTextHandoffStatus.ready || text == null) {
      setState(() => _busy = false);
      if (result.status == LocalTextHandoffStatus.invalidTarget ||
          result.status == LocalTextHandoffStatus.unsupportedStore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.structuredLocalFailure)),
        );
      }
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StructuredLocalTextPage(session: text),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    // The body coordinator was closed before handoff. Never resurrect its
    // stale revision; return to the caller, which can reopen the recovery.
    await _leave();
  }

  Future<void> _openInline(String blockId) async {
    if (_busy ||
        _exiting ||
        widget.session.state.phase != LocalStructuredPhase.editing) {
      return;
    }
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredLocalInlinePage(
            session: widget.session,
            blockId: blockId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // A rich input handoff closes the old body coordinator. Return to the
    // owner rather than reopening its stale local revision.
    if (mounted && widget.session.state.phase == LocalStructuredPhase.closed) {
      await _leave();
    }
  }

  Future<void> _openProperties(
    StructuredArticleDraft body,
    String blockId,
  ) async {
    if (_busy ||
        _exiting ||
        widget.session.state.phase != LocalStructuredPhase.editing ||
        !identical(widget.session.state.body, body)) {
      return;
    }
    final seed = StructuredBlockPropertiesSeed(body);
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredBlockPropertiesPage(
            session: widget.session,
            blockId: blockId,
            seed: seed,
          ),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openInsert(StructuredArticleDraft body, String anchor) async {
    if (_busy ||
        _exiting ||
        widget.session.state.phase != LocalStructuredPhase.editing ||
        !identical(widget.session.state.body, body)) {
      return;
    }
    final seed = StructuredInsertSeed(body);
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredInsertPage(
            session: widget.session,
            anchorId: anchor,
            seed: seed,
          ),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openList(StructuredArticleDraft body, String blockId) async {
    if (_busy ||
        _exiting ||
        widget.session.state.phase != LocalStructuredPhase.editing ||
        !identical(widget.session.state.body, body)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              StructuredListPage(session: widget.session, blockId: blockId),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows a strictly read-only comparison of the local base and current local
  /// body. The handoff captures both exact immutable snapshots; any session,
  /// account, recovery or body change makes the review route hide them rather
  /// than comparing a newly arrived value with an older one.
  Future<void> _openReview() async {
    if (_busy || _exiting) return;
    final state = widget.session.state;
    final base = state.baseBody;
    final body = state.body;
    if (base == null ||
        body == null ||
        !const {
          LocalStructuredPhase.recoveryChoice,
          LocalStructuredPhase.editing,
          LocalStructuredPhase.saveFailed,
          LocalStructuredPhase.conflict,
        }.contains(state.phase)) {
      return;
    }
    final seed = StructuredRecoveryReviewSeed(
      base: base,
      local: body,
      remoteStatus: state.remoteStatus,
      baseComparison: state.baseComparison,
    );
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              StructuredRecoveryReviewPage(session: widget.session, seed: seed),
        ),
      );
    } finally {
      seed.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(
    StructuredArticleDraft Function(StructuredArticleDraft) operation,
  ) {
    try {
      widget.session.edit(operation);
    } on ArgumentError {
      // The body may have changed while a confirmation was open. Keep the
      // current snapshot; never repair by guessing a different block.
    } on FormatException {
      // Validation rejects destructive or unsupported transformations.
    } on StateError {
      // A stale or unsupported operation is intentionally a no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A direct identity getter fences even authenticators whose event stream
    // was delayed. Never retain a private body from an earlier state in build.
    _readingState = true;
    final LocalStructuredState state;
    try {
      state = widget.session.state;
    } finally {
      _readingState = false;
    }
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
          title: Text(l10n.structuredLocalTitle),
          actions: [
            PopupMenuButton<_BodyHistoryAction>(
              key: const ValueKey('structured-history-menu'),
              tooltip: l10n.structuredHistoryTitle,
              enabled:
                  state.body != null &&
                  const {
                    LocalStructuredPhase.editing,
                    LocalStructuredPhase.saveFailed,
                    LocalStructuredPhase.conflict,
                  }.contains(state.phase) &&
                  !_busy &&
                  !_exiting,
              icon: const Icon(Icons.history),
              onSelected: (action) {
                final generation = _historyMenuGeneration;
                final selectedBody = _historyMenuBody;
                _historyMenuGeneration = null;
                _historyMenuBody = null;
                final current = widget.session.state;
                if (_busy ||
                    _exiting ||
                    selectedBody == null ||
                    !identical(current.body, selectedBody)) {
                  return;
                }
                if (action == _BodyHistoryAction.exportBody) {
                  unawaited(_openTransfer(import: false));
                  return;
                }
                final history = widget.session.captureBodyHistory();
                if (generation == null || history?.generation != generation) {
                  return;
                }
                switch (action) {
                  case _BodyHistoryAction.undo:
                    widget.session.undoBody();
                  case _BodyHistoryAction.redo:
                    widget.session.redoBody();
                  case _BodyHistoryAction.review:
                    unawaited(_openHistory());
                  case _BodyHistoryAction.importBody:
                    unawaited(_openTransfer(import: true));
                  case _BodyHistoryAction.exportBody:
                    break;
                }
              },
              onCanceled: () {
                _historyMenuGeneration = null;
                _historyMenuBody = null;
              },
              itemBuilder: (context) {
                final history = widget.session.captureBodyHistory();
                _historyMenuGeneration = history?.generation;
                _historyMenuBody = widget.session.state.body;
                return [
                  PopupMenuItem(
                    key: const ValueKey('structured-history-undo'),
                    value: _BodyHistoryAction.undo,
                    enabled: history?.canUndo == true,
                    child: Text(l10n.structuredHistoryUndo),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('structured-history-redo'),
                    value: _BodyHistoryAction.redo,
                    enabled: history?.canRedo == true,
                    child: Text(l10n.structuredHistoryRedo),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('structured-history-open'),
                    value: _BodyHistoryAction.review,
                    enabled: history != null,
                    child: Text(l10n.structuredHistoryTitle),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: const ValueKey('structured-transfer-export'),
                    value: _BodyHistoryAction.exportBody,
                    enabled: _historyMenuBody != null,
                    child: Text(l10n.structuredTransferExportTitle),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('structured-transfer-import'),
                    value: _BodyHistoryAction.importBody,
                    enabled: history != null,
                    child: Text(l10n.structuredTransferImportTitle),
                  ),
                ];
              },
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(context, state)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LocalStructuredState state) {
    final l10n = context.l10n;
    if (state.phase == LocalStructuredPhase.initial ||
        state.phase == LocalStructuredPhase.opening) {
      return Center(
        child: Semantics(liveRegion: true, child: Text(l10n.structuredLoading)),
      );
    }
    if (state.phase == LocalStructuredPhase.invalidated ||
        state.phase == LocalStructuredPhase.closed) {
      return Center(child: Text(l10n.structuredSessionChanged));
    }
    if (state.phase == LocalStructuredPhase.cancelled) {
      return Center(child: Text(l10n.structuredRecoveryBody));
    }
    if (state.phase == LocalStructuredPhase.unavailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.page),
          child: Text(_unavailableMessage(context, state.remoteStatus)),
        ),
      );
    }
    if (state.phase == LocalStructuredPhase.localReadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.page),
          child: Text(l10n.structuredLocalFailure),
        ),
      );
    }
    if (state.phase == LocalStructuredPhase.recoveryChoice) {
      return ListView(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        children: [
          Text(l10n.structuredLocalIntro),
          Text(
            '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
          ),
          const SizedBox(height: NoWaveSpacing.medium),
          Text(
            l10n.structuredRecoveryTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(l10n.structuredRecoveryBody),
          if (_comparisonText(context, state.baseComparison)
              case final String message)
            Text(message),
          const SizedBox(height: NoWaveSpacing.medium),
          OutlinedButton(
            key: const ValueKey('structured-review-open'),
            onPressed: _busy ? null : _openReview,
            child: Text(l10n.structuredReviewOpen),
          ),
          FilledButton(
            onPressed: _busy ? null : () => widget.session.resumeRecovery(),
            child: Text(l10n.structuredRecoveryResume),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _discardRecovery,
            child: Text(l10n.structuredRecoveryDiscard),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    widget.session.cancelRecovery();
                    unawaited(_leave());
                  },
            child: Text(l10n.actionCancel),
          ),
        ],
      );
    }
    final body = state.body;
    if (body == null) {
      return Center(
        child: Text(
          state.phase == LocalStructuredPhase.conflict
              ? l10n.structuredConflict
              : l10n.structuredLocalFailure,
        ),
      );
    }
    final editable =
        state.phase == LocalStructuredPhase.editing && !_busy && !_exiting;
    return ListView(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      children: [
        Text(l10n.structuredLocalIntro),
        Text(
          '${l10n.structuredEdition}: ${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
        ),
        const SizedBox(height: NoWaveSpacing.small),
        Text(l10n.structuredLocalLimited),
        const SizedBox(height: NoWaveSpacing.small),
        Semantics(liveRegion: true, child: Text(_status(context, state))),
        if (_comparisonText(context, state.baseComparison)
            case final String message)
          Text(message),
        // This view is for an adopted recovery; the separate local recovery
        // review remains available before the author chooses to resume it.
        OutlinedButton.icon(
          onPressed: _busy || _exiting ? null : _openComparison,
          icon: const Icon(Icons.compare_arrows),
          label: Text(l10n.structuredCompareTitle),
        ),
        if (state.phase == LocalStructuredPhase.saveFailed)
          TextButton(
            onPressed: () => widget.session.retrySave(),
            child: Text(l10n.actionRetry),
          ),
        const SizedBox(height: NoWaveSpacing.medium),
        if (body.blocks.length >= 200) Text(l10n.structuredInsertBlockLimit),
        for (var index = 0; index < body.blocks.length; index++)
          _StructuredBlockCard(
            key: ValueKey(body.blocks[index]['id']),
            block: body.blocks[index],
            position: index + 1,
            editable: editable,
            canMoveUp: index > 0,
            canMoveDown: index < body.blocks.length - 1,
            canRemove: body.blocks.length > 1,
            canInsert: body.blocks.length < 200,
            canBold: body.version == 1,
            canEditText: widget.session.store is StructuredTextSessionStore,
            canEditInline: body.version == 1,
            onProperties: () =>
                _openProperties(body, body.blocks[index]['id'] as String),
            onInsert: () =>
                _openInsert(body, body.blocks[index]['id'] as String),
            onList: () => _openList(body, body.blocks[index]['id'] as String),
            onInline: () => _openInline(body.blocks[index]['id'] as String),
            onText: () => _openText(body.blocks[index]['id'] as String),
            onMoveUp: () => _move(body.blocks[index]['id'] as String, -1),
            onMoveDown: () => _move(body.blocks[index]['id'] as String, 1),
            onRemove: () => _remove(body.blocks[index]['id'] as String),
            onBold: () => _toggleBold(body.blocks[index]),
          ),
      ],
    );
  }

  String _unavailableMessage(
    BuildContext context,
    StructuredEditionReadStatus? status,
  ) {
    final l10n = context.l10n;
    return switch (status) {
      StructuredEditionReadStatus.unsupportedDocument =>
        l10n.structuredUnsupported,
      StructuredEditionReadStatus.invalidResponse =>
        l10n.structuredInvalidResponse,
      StructuredEditionReadStatus.editionMismatch =>
        l10n.structuredEditionMismatch,
      StructuredEditionReadStatus.authenticationRequired =>
        l10n.structuredAuthRequired,
      StructuredEditionReadStatus.unavailable => l10n.structuredOffline,
      StructuredEditionReadStatus.sessionChanged =>
        l10n.structuredSessionChanged,
      _ => l10n.structuredUnavailable,
    };
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

  String? _comparisonText(
    BuildContext context,
    StructuredBaseComparison? comparison,
  ) => switch (comparison) {
    StructuredBaseComparison.bodyDiffers ||
    StructuredBaseComparison.metadataDiffers =>
      context.l10n.structuredChangedBase,
    StructuredBaseComparison.remoteUnavailable ||
    StructuredBaseComparison.metadataUnknown ||
    StructuredBaseComparison.representedFieldsMatch =>
      context.l10n.structuredUnknownBase,
    _ => null,
  };

  void _move(String id, int delta) {
    _edit((body) {
      final from = body.blocks.indexWhere((block) => block['id'] == id);
      final to = from + delta;
      if (from < 0 || to < 0 || to >= body.blocks.length) return body;
      return body.move(id, to);
    });
  }

  void _toggleBold(Map<String, Object?> block) {
    final id = block['id'] as String;
    _edit((body) {
      final current = body.blocks.firstWhere((entry) => entry['id'] == id);
      final type = current['type'];
      final enabled = !_firstRunIsBold(current);
      if (type == 'list') {
        return body.setListRunMark(id, 0, 0, 'bold', enabled: enabled);
      }
      if (const {'paragraph', 'heading', 'quote'}.contains(type)) {
        return body.setTextRunMark(id, 0, 'bold', enabled: enabled);
      }
      return body;
    });
  }
}

class _StructuredBlockCard extends StatelessWidget {
  const _StructuredBlockCard({
    super.key,
    required this.block,
    required this.position,
    required this.editable,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
    required this.canInsert,
    required this.canBold,
    required this.canEditText,
    required this.canEditInline,
    required this.onProperties,
    required this.onInsert,
    required this.onList,
    required this.onInline,
    required this.onText,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.onBold,
  });
  final Map<String, Object?> block;
  final int position;
  final bool editable;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;
  final bool canInsert;
  final bool canBold;
  final bool canEditText;
  final bool canEditInline;
  final VoidCallback onProperties;
  final VoidCallback onInsert;
  final VoidCallback onList;
  final VoidCallback onInline;
  final VoidCallback onText;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;
  final VoidCallback onBold;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = block['type'];
    final label = switch (type) {
      'paragraph' => l10n.structuredParagraph,
      'heading' => l10n.structuredHeading,
      'quote' => l10n.structuredQuote,
      'list' => l10n.structuredList,
      'image' => l10n.structuredImage,
      'code' => l10n.structuredCode,
      _ => l10n.structuredUnavailable,
    };
    final formatable = const {
      'paragraph',
      'heading',
      'quote',
      'list',
    }.contains(type);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.structuredBlock} $position: $label',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._preview(context),
            Wrap(
              children: [
                IconButton(
                  tooltip: l10n.structuredMoveUp,
                  onPressed: editable && canMoveUp ? onMoveUp : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: l10n.structuredMoveDown,
                  onPressed: editable && canMoveDown ? onMoveDown : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: l10n.structuredRemove,
                  onPressed: editable && canRemove ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: l10n.structuredInsertBlockAfter,
                  onPressed: editable && canInsert ? onInsert : null,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                if (type == 'list')
                  IconButton(
                    tooltip: l10n.structuredListOpen,
                    onPressed: editable ? onList : null,
                    icon: const Icon(Icons.format_list_bulleted),
                  ),
                if (const {
                  'image',
                  'code',
                  'quote',
                  'heading',
                  'list',
                }.contains(type))
                  IconButton(
                    tooltip: l10n.structuredPropertiesOpen,
                    onPressed: editable ? onProperties : null,
                    icon: const Icon(Icons.tune),
                  ),
                if (canEditText &&
                    const {'paragraph', 'heading', 'quote'}.contains(type) &&
                    !block.containsKey('inlines'))
                  IconButton(
                    tooltip: l10n.structuredTextOpen,
                    onPressed: editable ? onText : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (canEditInline &&
                    const {
                      'paragraph',
                      'heading',
                      'quote',
                      'list',
                    }.contains(type))
                  IconButton(
                    tooltip: l10n.structuredInlineOpen,
                    onPressed: editable ? onInline : null,
                    icon: const Icon(Icons.format_paint_outlined),
                  ),
                if (formatable && canBold)
                  IconButton(
                    tooltip: l10n.structuredBold,
                    isSelected: _firstRunIsBold(block),
                    onPressed: editable ? onBold : null,
                    icon: const Icon(Icons.format_bold),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _preview(BuildContext context) {
    final l10n = context.l10n;
    String safe(String value) =>
        isWellFormedUtf16(value) ? value : l10n.structuredInlineUnsupported;
    switch (block['type']) {
      case 'paragraph':
      case 'heading':
      case 'quote':
        return [
          Text(safe(block['text'] as String)),
          if (block['attribution'] case final String attribution)
            Text('${l10n.structuredAttribution}: ${safe(attribution)}'),
        ];
      case 'list':
        return [
          for (final item in block['items'] as List)
            Text('• ${safe(item as String)}'),
        ];
      case 'image':
        return [
          Text(safe(block['src'] as String)),
          Text('${l10n.structuredAlt}: ${safe(block['alt'] as String)}'),
          if (block['caption'] case final String caption)
            Text('${l10n.structuredCaption}: ${safe(caption)}'),
        ];
      case 'code':
        return [
          Text(safe(block['language'] as String)),
          Text(safe(block['code'] as String)),
        ];
      default:
        return [];
    }
  }
}

/// A missing inline array means a single unformatted fallback run.
bool _firstRunIsBold(Map<String, Object?> block) {
  final Object? runs = block['type'] == 'list'
      ? (block['itemInlines'] is List
            ? (block['itemInlines'] as List).first
            : null)
      : block['inlines'];
  if (runs is! List || runs.isEmpty || runs.first is! Map) return false;
  final marks = (runs.first as Map)['marks'];
  return marks is List && marks.contains('bold');
}
