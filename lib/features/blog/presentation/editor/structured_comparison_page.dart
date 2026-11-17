import 'dart:async';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:belog/features/blog/presentation/editor/structured_comparison_card.dart';
import 'package:flutter/material.dart';

/// One-shot handoff. Both owner and receiver clear their references on exit.
class StructuredComparisonSeed {
  StructuredComparisonSeed(this._capture);
  StructuredComparisonCapture? _capture;
  StructuredComparisonCapture? take() {
    final result = _capture;
    _capture = null;
    return result;
  }

  void clear() => _capture = null;
}

enum _Pair { baseLocal, baseRemote, remoteLocal }

enum _Filter { changed, all, added, removed, modified, moved }

/// Advisory inspection of exact body snapshots. No fetch, writes, or merges.
class StructuredComparisonPage extends StatefulWidget {
  const StructuredComparisonPage({
    super.key,
    required this.session,
    required this.seed,
  });
  final LocalStructuredSession session;
  final StructuredComparisonSeed seed;
  @override
  State<StructuredComparisonPage> createState() =>
      _StructuredComparisonPageState();
}

class _StructuredComparisonPageState extends State<StructuredComparisonPage> {
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredComparisonCapture? _capture;
  StructuredDocumentComparison? _comparison;
  _Pair _pair = _Pair.baseLocal;
  _Filter _filter = _Filter.changed;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    final capture = widget.seed.take();
    final state = widget.session.state;
    if (capture != null &&
        identical(state.body, capture.local) &&
        _allowed(state)) {
      _capture = capture;
      _compare();
    }
    _subscription = widget.session.changes.listen(_onState);
  }

  bool _allowed(LocalStructuredState state) =>
      state.phase == LocalStructuredPhase.editing ||
      state.phase == LocalStructuredPhase.saveFailed ||
      state.phase == LocalStructuredPhase.conflict;

  void _onState(LocalStructuredState state) {
    final capture = _capture;
    if (capture != null &&
        (!_allowed(state) || !identical(state.body, capture.local))) {
      _capture = null;
      _comparison = null;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (mounted && !_reading) setState(() {});
  }

  void _compare() {
    final capture = _capture;
    if (capture == null) return;
    final remote = capture.remote;
    _comparison = switch (_pair) {
      _Pair.baseLocal => StructuredDocumentComparison.between(
        capture.base,
        capture.local,
      ),
      _Pair.baseRemote =>
        remote == null
            ? null
            : StructuredDocumentComparison.between(capture.base, remote),
      _Pair.remoteLocal =>
        remote == null
            ? null
            : StructuredDocumentComparison.between(remote, capture.local),
    };
  }

  @override
  void dispose() {
    widget.seed.clear();
    _capture = null;
    _comparison = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  String _pairLabel(BuildContext context, _Pair pair) => switch (pair) {
    _Pair.baseLocal => context.l10n.structuredCompareBaseLocal,
    _Pair.baseRemote => context.l10n.structuredCompareBaseRemote,
    _Pair.remoteLocal => context.l10n.structuredCompareRemoteLocal,
  };

  String _filterLabel(BuildContext context, _Filter filter) => switch (filter) {
    _Filter.changed => context.l10n.structuredCompareChanged,
    _Filter.all => context.l10n.structuredCompareAll,
    _Filter.added => context.l10n.structuredCompareAdded,
    _Filter.removed => context.l10n.structuredCompareRemoved,
    _Filter.modified => context.l10n.structuredCompareModified,
    _Filter.moved => context.l10n.structuredCompareMoved,
  };

  bool _matches(StructuredBlockChange entry) => switch (_filter) {
    _Filter.changed => entry.changed,
    _Filter.all => true,
    _Filter.added => entry.added,
    _Filter.removed => entry.removed,
    _Filter.modified => entry.modified,
    _Filter.moved => entry.moved,
  };

  @override
  Widget build(BuildContext context) {
    // The getter checks the fence even if its event has not yet arrived.
    _reading = true;
    final LocalStructuredState state;
    try {
      state = widget.session.state;
    } finally {
      _reading = false;
    }
    if (_capture != null &&
        (!_allowed(state) || !identical(state.body, _capture!.local))) {
      _capture = null;
      _comparison = null;
    }
    final l10n = context.l10n;
    final capture = _capture;
    final comparison = _comparison;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredCompareTitle)),
      body: SafeArea(
        child: capture == null || comparison == null
            ? Center(child: Text(l10n.structuredSessionChanged))
            : _content(context, capture, comparison),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    StructuredComparisonCapture capture,
    StructuredDocumentComparison comparison,
  ) {
    final l10n = context.l10n;
    final visible = comparison.entries.where(_matches).toList(growable: false);
    return ListView.builder(
      padding: const EdgeInsets.all(NoWaveSpacing.page),
      itemCount: visible.length + 1,
      itemBuilder: (context, index) {
        if (index > 0) {
          return StructuredComparisonCard(
            key: ValueKey(visible[index - 1].id),
            change: visible[index - 1],
            comparison: comparison,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.structuredCompareIntro),
            const SizedBox(height: NoWaveSpacing.small),
            Text(l10n.structuredCompareRemoteWarning),
            if (capture.remote == null)
              Text(l10n.structuredCompareRemoteMissing),
            const SizedBox(height: NoWaveSpacing.medium),
            DropdownButtonFormField<_Pair>(
              initialValue: _pair,
              decoration: InputDecoration(
                labelText: l10n.structuredComparePair,
              ),
              items: [
                for (final pair in _Pair.values)
                  if (pair == _Pair.baseLocal || capture.remote != null)
                    DropdownMenuItem(
                      value: pair,
                      child: Text(_pairLabel(context, pair)),
                    ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _pair = value;
                  _compare();
                });
              },
            ),
            const SizedBox(height: NoWaveSpacing.medium),
            Text(
              '${l10n.structuredCompareBefore}: ${comparison.before.version} · ${l10n.structuredCompareAfter}: ${comparison.after.version}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (comparison.versionChanged)
              Text(l10n.structuredCompareVersionChanged),
            Text(
              '${l10n.structuredCompareAdded}: ${comparison.addedCount} · ${l10n.structuredCompareRemoved}: ${comparison.removedCount} · ${l10n.structuredCompareModified}: ${comparison.modifiedCount} · ${l10n.structuredCompareMoved}: ${comparison.movedCount}',
            ),
            Text(l10n.structuredCompareCountsNote),
            const SizedBox(height: NoWaveSpacing.medium),
            DropdownButtonFormField<_Filter>(
              initialValue: _filter,
              decoration: InputDecoration(
                labelText: l10n.structuredCompareFilter,
              ),
              items: [
                for (final filter in _Filter.values)
                  DropdownMenuItem(
                    value: filter,
                    child: Text(_filterLabel(context, filter)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _filter = value);
              },
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NoWaveSpacing.medium,
                ),
                child: Text(l10n.structuredCompareEmpty),
              ),
          ],
        );
      },
    );
  }
}
