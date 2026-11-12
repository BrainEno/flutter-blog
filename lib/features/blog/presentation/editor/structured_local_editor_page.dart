import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:flutter/material.dart';

/// A deliberately limited local-only editor. It never constructs a server
/// request. Text input is intentionally absent until invalid intermediate
/// input can be recovered independently of the validated body snapshot.
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
  bool _busy = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.session.changes.listen((state) {
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
    final editable = state.phase == LocalStructuredPhase.editing && !_busy;
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
        if (state.phase == LocalStructuredPhase.saveFailed)
          TextButton(
            onPressed: () => widget.session.retrySave(),
            child: Text(l10n.actionRetry),
          ),
        const SizedBox(height: NoWaveSpacing.medium),
        for (var index = 0; index < body.blocks.length; index++)
          _StructuredBlockCard(
            key: ValueKey(body.blocks[index]['id']),
            block: body.blocks[index],
            position: index + 1,
            editable: editable,
            canMoveUp: index > 0,
            canMoveDown: index < body.blocks.length - 1,
            canRemove: body.blocks.length > 1,
            canBold: body.version == 1,
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
    required this.canBold,
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
  final bool canBold;
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
    switch (block['type']) {
      case 'paragraph':
      case 'heading':
      case 'quote':
        return [
          Text(block['text'] as String),
          if (block['attribution'] case final String attribution)
            Text('${l10n.structuredAttribution}: $attribution'),
        ];
      case 'list':
        return [for (final item in block['items'] as List) Text('• $item')];
      case 'image':
        return [
          Text(block['src'] as String),
          Text('${l10n.structuredAlt}: ${block['alt']}'),
          if (block['caption'] case final String caption)
            Text('${l10n.structuredCaption}: $caption'),
        ];
      case 'code':
        return [
          Text(block['language'] as String),
          Text(block['code'] as String),
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
