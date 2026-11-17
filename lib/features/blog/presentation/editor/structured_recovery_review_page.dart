import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_recovery_comparison.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:flutter/material.dart';

/// One-shot handoff for an exact local review snapshot. It is deliberately not
/// a recovery token and has no methods that can edit, discard, enqueue, or
/// publish the document. The owner must clear it after navigation returns.
class StructuredRecoveryReviewSeed {
  StructuredRecoveryReviewSeed({
    required StructuredArticleDraft base,
    required StructuredArticleDraft local,
    required StructuredEditionReadStatus? remoteStatus,
    required StructuredBaseComparison? baseComparison,
  }) : _snapshot = StructuredRecoveryReviewSnapshot._(
         base: base,
         local: local,
         remoteStatus: remoteStatus,
         baseComparison: baseComparison,
       );

  StructuredRecoveryReviewSnapshot? _snapshot;

  StructuredRecoveryReviewSnapshot? take() {
    final snapshot = _snapshot;
    _snapshot = null;
    return snapshot;
  }

  void clear() => _snapshot = null;
}

/// Immutable route input. Both documents are existing immutable drafts; this
/// object never serializes them, so optional fields retain their exact shape.
class StructuredRecoveryReviewSnapshot {
  const StructuredRecoveryReviewSnapshot._({
    required this.base,
    required this.local,
    required this.remoteStatus,
    required this.baseComparison,
  });

  final StructuredArticleDraft base;
  final StructuredArticleDraft local;
  final StructuredEditionReadStatus? remoteStatus;
  final StructuredBaseComparison? baseComparison;
}

/// Read-only review of an existing local structured recovery. It compares the
/// original local base to the currently held local snapshot. It does not make
/// a network request, assert that the server is current, or apply any edit.
class StructuredRecoveryReviewPage extends StatefulWidget {
  const StructuredRecoveryReviewPage({
    super.key,
    required this.session,
    required this.seed,
  });

  final LocalStructuredSession session;
  final StructuredRecoveryReviewSeed seed;

  @override
  State<StructuredRecoveryReviewPage> createState() =>
      _StructuredRecoveryReviewPageState();
}

class _StructuredRecoveryReviewPageState
    extends State<StructuredRecoveryReviewPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredRecoveryReviewSnapshot? _snapshot;
  StructuredRecoveryComparison? _comparison;
  bool _unsupported = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.seed.take(), widget.session.state);
    _subscription = widget.session.changes.listen(_onState);
  }

  void _onState(LocalStructuredState state) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (!_matches(state, snapshot)) {
      _snapshot = null;
      _comparison = null;
      _unsupported = false;
      if (mounted && !_reading) setState(() {});
    }
  }

  bool _matches(
    LocalStructuredState state,
    StructuredRecoveryReviewSnapshot snapshot,
  ) =>
      (state.phase == LocalStructuredPhase.recoveryChoice ||
          state.phase == LocalStructuredPhase.editing ||
          state.phase == LocalStructuredPhase.saveFailed ||
          state.phase == LocalStructuredPhase.conflict) &&
      identical(state.baseBody, snapshot.base) &&
      identical(state.body, snapshot.local);

  void _adopt(
    StructuredRecoveryReviewSnapshot? snapshot,
    LocalStructuredState state,
  ) {
    if (snapshot == null || !_matches(state, snapshot)) return;
    _snapshot = snapshot;
    try {
      _comparison = StructuredRecoveryComparison.compare(
        base: snapshot.base,
        local: snapshot.local,
      );
    } on FormatException {
      // A version mismatch is not a cue to flatten or reinterpret documents.
      _unsupported = true;
    }
  }

  @override
  void dispose() {
    widget.seed.clear();
    _snapshot = null;
    _comparison = null;
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
    final snapshot = _snapshot;
    if (snapshot != null && !_matches(state, snapshot)) {
      _snapshot = null;
      _comparison = null;
      _unsupported = false;
    }
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredReviewTitle)),
      body: SafeArea(
        child: _snapshot == null
            ? _stateChanged(context)
            : _unsupported
            ? _unsupportedDocument(context)
            : _review(context, _snapshot!, _comparison!),
      ),
    );
  }

  Widget _stateChanged(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      child: Semantics(
        liveRegion: true,
        child: Text(context.l10n.structuredReviewStateChanged),
      ),
    ),
  );

  Widget _unsupportedDocument(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      child: Semantics(
        liveRegion: true,
        child: Text(context.l10n.structuredReviewUnsupported),
      ),
    ),
  );

  Widget _review(
    BuildContext context,
    StructuredRecoveryReviewSnapshot snapshot,
    StructuredRecoveryComparison comparison,
  ) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      children: [
        Text(l10n.structuredReviewIntro),
        const SizedBox(height: NoWaveSpacing.small),
        Semantics(
          liveRegion: true,
          child: Text(_remoteExplanation(context, snapshot)),
        ),
        Text(
          '${l10n.structuredEdition}: '
          '${contentEditionLabel(l10n, widget.session.key.locale) ?? widget.session.key.locale}',
        ),
        Text(
          '${l10n.structuredReviewDocumentVersion}: '
          '${comparison.baseVersion}',
        ),
        const SizedBox(height: NoWaveSpacing.medium),
        _SummaryCard(comparison: comparison),
        const SizedBox(height: NoWaveSpacing.medium),
        if (!comparison.hasChanges)
          Semantics(
            liveRegion: true,
            child: Text(l10n.structuredReviewNoChanges),
          )
        else ...[
          Text(
            l10n.structuredReviewChanges,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          for (final change in comparison.changes) _ChangeCard(change: change),
        ],
      ],
    );
  }

  String _remoteExplanation(
    BuildContext context,
    StructuredRecoveryReviewSnapshot snapshot,
  ) {
    final l10n = context.l10n;
    if (snapshot.remoteStatus == StructuredEditionReadStatus.found) {
      return switch (snapshot.baseComparison) {
        StructuredBaseComparison.bodyDiffers ||
        StructuredBaseComparison.metadataDiffers =>
          l10n.structuredReviewRemoteDiffers,
        StructuredBaseComparison.representedFieldsMatch =>
          l10n.structuredReviewRemoteMatched,
        StructuredBaseComparison.metadataUnknown =>
          l10n.structuredReviewRemoteUnknown,
        _ => l10n.structuredReviewLocalOnly,
      };
    }
    if (snapshot.remoteStatus == StructuredEditionReadStatus.unavailable ||
        snapshot.remoteStatus ==
            StructuredEditionReadStatus.notInAuthorWindow) {
      return l10n.structuredReviewRemoteUnavailable;
    }
    return l10n.structuredReviewRemoteUnknown;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.comparison});

  final StructuredRecoveryComparison comparison;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.structuredReviewSummary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: NoWaveSpacing.small),
            _count(l10n.structuredReviewAdded, comparison.addedCount),
            _count(l10n.structuredReviewRemoved, comparison.removedCount),
            _count(l10n.structuredReviewMoved, comparison.movedCount),
            _count(l10n.structuredReviewModified, comparison.modifiedCount),
            _count(
              l10n.structuredReviewUnchanged,
              comparison.unchangedBlockCount,
            ),
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int count) =>
      Semantics(label: '$label: $count', child: Text('$label: $count'));
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final StructuredBlockChange change;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = change.local ?? change.base!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.structuredBlock}: ${snapshot.position + 1} '
              '(${_typeLabel(l10n, snapshot.type)})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${l10n.structuredReviewBlockId}: ${change.id}'),
            const SizedBox(height: NoWaveSpacing.small),
            Wrap(
              spacing: NoWaveSpacing.small,
              runSpacing: NoWaveSpacing.small,
              children: [
                for (final kind in StructuredBlockChangeKind.values)
                  if (change.kinds.contains(kind))
                    Chip(label: Text(_kindLabel(l10n, kind))),
              ],
            ),
            if (change.wasMoved) _positions(context, change),
            if (change.wasAdded)
              _snapshotPanel(
                context,
                title: l10n.structuredReviewLocalBlock,
                snapshot: change.local!,
              ),
            if (change.wasRemoved)
              _snapshotPanel(
                context,
                title: l10n.structuredReviewOriginalBlock,
                snapshot: change.base!,
              ),
            if (change.wasModified) ...[
              const SizedBox(height: NoWaveSpacing.small),
              Text(
                l10n.structuredReviewFieldChanges,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final field in change.fields) _fieldChange(context, field),
            ],
          ],
        ),
      ),
    );
  }

  Widget _positions(BuildContext context, StructuredBlockChange change) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.small),
      child: Text(
        '${l10n.structuredReviewOriginalPosition}: '
        '${change.base!.position + 1} · '
        '${l10n.structuredReviewLocalPosition}: ${change.local!.position + 1}',
      ),
    );
  }

  Widget _fieldChange(BuildContext context, StructuredBlockFieldChange field) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fieldLabel(l10n, field.field)),
          Text(
            '${l10n.structuredReviewBefore}: ${_value(context, field.hadBefore, field.before)}',
          ),
          Text(
            '${l10n.structuredReviewAfter}: ${_value(context, field.hasAfter, field.after)}',
          ),
        ],
      ),
    );
  }

  Widget _snapshotPanel(
    BuildContext context, {
    required String title,
    required StructuredBlockSnapshot snapshot,
  }) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: NoWaveSpacing.small),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title),
        children: [
          for (final entry in snapshot.fields.entries)
            if (entry.key != 'id' && entry.key != 'type')
              Padding(
                padding: const EdgeInsets.only(
                  left: NoWaveSpacing.small,
                  right: NoWaveSpacing.small,
                  bottom: NoWaveSpacing.small,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(_fieldLabel(l10n, entry.key)),
                    ),
                    const SizedBox(width: NoWaveSpacing.small),
                    Expanded(
                      flex: 3,
                      child: Text(_value(context, true, entry.value)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n, StructuredBlockChangeKind kind) =>
      switch (kind) {
        StructuredBlockChangeKind.added => l10n.structuredReviewAdded,
        StructuredBlockChangeKind.removed => l10n.structuredReviewRemoved,
        StructuredBlockChangeKind.moved => l10n.structuredReviewMoved,
        StructuredBlockChangeKind.modified => l10n.structuredReviewModified,
      };

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
    'paragraph' => l10n.structuredParagraph,
    'heading' => l10n.structuredHeading,
    'quote' => l10n.structuredQuote,
    'list' => l10n.structuredList,
    'image' => l10n.structuredImage,
    'code' => l10n.structuredCode,
    _ => l10n.structuredUnavailable,
  };

  String _fieldLabel(AppLocalizations l10n, String field) => switch (field) {
    'text' => l10n.structuredReviewFieldText,
    'inlines' => l10n.structuredReviewFieldInlineRuns,
    'itemInlines' => l10n.structuredReviewFieldListRuns,
    'items' => l10n.structuredReviewFieldItems,
    'alt' => l10n.structuredPropertiesAlt,
    'caption' => l10n.structuredCaption,
    'src' => l10n.structuredReviewFieldImageSource,
    'level' => l10n.structuredPropertiesLevel,
    'ordered' => l10n.structuredPropertiesOrdered,
    'attribution' => l10n.structuredPropertiesAttribution,
    'language' => l10n.structuredPropertiesLanguage,
    'code' => l10n.structuredPropertiesCode,
    _ => field,
  };

  String _value(BuildContext context, bool present, Object? value) {
    if (!present) return context.l10n.structuredReviewMissing;
    return _formatValue(context, value);
  }
}

String _formatValue(BuildContext context, Object? value, {int depth = 0}) {
  final l10n = context.l10n;
  if (value == null) return l10n.structuredReviewNull;
  if (value is String) {
    return isWellFormedUtf16(value) ? value : l10n.structuredInlineUnsupported;
  }
  if (value is num || value is bool) return '$value';
  if (depth >= 4) return l10n.structuredReviewNestedValue;
  if (value is List) {
    return '[${value.map((entry) => _formatValue(context, entry, depth: depth + 1)).join(', ')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .where((entry) => entry.key is String)
        .map(
          (entry) =>
              '${entry.key}: '
              '${_formatValue(context, entry.value, depth: depth + 1)}',
        );
    return '{${entries.join(', ')}}';
  }
  return l10n.structuredReviewNestedValue;
}
