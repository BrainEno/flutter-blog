import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/edition_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:belog/features/blog/domain/usecase/open_indexed_recovery.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:belog/features/blog/presentation/editor/structured_local_editor_page.dart';
import 'package:flutter/material.dart';

/// A local index, independent of the remote author-list request. No body or
/// metadata is read until the author explicitly opens one exact local row.
class StructuredRecoveryCatalogPage extends StatefulWidget {
  const StructuredRecoveryCatalogPage({
    super.key,
    required this.list,
    required this.opener,
    required this.user,
    required this.fence,
  });
  final ListStructuredRecoveries list;
  final OpenStructuredEditingSession opener;
  final AppUserCubit user;
  final NowaveSessionFence fence;

  @override
  State<StructuredRecoveryCatalogPage> createState() =>
      _StructuredRecoveryCatalogPageState();
}

class _StructuredRecoveryCatalogPageState
    extends State<StructuredRecoveryCatalogPage> {
  late final StreamSubscription<void> _identitySubscription;
  final _editorIdentityEvents = StreamController<void>.broadcast(sync: true);

  List<StructuredRecoveryIndexEntry> _entries = [];
  int? _cursor;
  bool _loading = false;
  bool _failed = false;
  bool _obsolete = false;
  bool _opening = false;
  int _generation = 0;

  bool get _active {
    final state = widget.user.state;
    return !_obsolete &&
        state is AppUserLoggedIn &&
        state.user.id == widget.fence.userId &&
        identical(widget.list.identity, widget.opener.identity) &&
        widget.list.isActive(widget.fence);
  }

  @override
  void initState() {
    super.initState();
    _identitySubscription = widget.list.identity.identityChanges.listen(
      (_) => _identityChanged(),
    );
    widget.user.identityRevision.addListener(_identityChanged);
    unawaited(_refresh());
  }

  void _identityChanged() {
    if (!_editorIdentityEvents.isClosed) _editorIdentityEvents.add(null);
    if (!_active && !_obsolete) {
      _obsolete = true;
      _generation++;
      _entries = [];
      _cursor = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refresh() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (_loading || !_active) {
      _identityChanged();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final result = await widget.list(
      fence: widget.fence,
      afterRowId: reset ? null : _cursor,
      isCurrent: () => mounted && generation == _generation && _active,
    );
    if (!mounted || generation != _generation) return;
    if (!_active || result.status == StructuredRecoveryListStatus.obsolete) {
      _identityChanged();
      return;
    }
    setState(() {
      _loading = false;
      if (result.status == StructuredRecoveryListStatus.unavailable) {
        _failed = true;
      } else {
        final page = result.page!;
        _entries = reset
            ? page.entries.toList()
            : [..._entries, ...page.entries];
        _cursor = page.nextCursor;
      }
    });
  }

  Future<void> _open(StructuredRecoveryIndexEntry entry) async {
    if (_opening || _loading || !_active || entry.key == null) {
      _identityChanged();
      return;
    }
    _opening = true;
    try {
      final session = openIndexedRecovery(
        entry: entry,
        fence: widget.fence,
        opener: OpenStructuredEditingSession(
          reader: widget.opener.reader,
          store: widget.opener.store,
          identity: _AccountBoundIdentity(
            inner: widget.opener.identity,
            isCurrent: () => mounted && _active,
            changes: _editorIdentityEvents.stream,
          ),
        ),
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StructuredLocalEditorPage(session: session),
        ),
      );
    } finally {
      _opening = false;
    }
    if (mounted && _active) await _refresh();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_identitySubscription.cancel());
    widget.user.identityRevision.removeListener(_identityChanged);
    unawaited(_editorIdentityEvents.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Direct getter check also fences delayed identity notifications.
    final active = _active;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.structuredCatalogTitle)),
      body: !active
          ? Center(child: Text(l10n.structuredSessionChanged))
          : ListView(
              padding: const EdgeInsets.all(NoWaveSpacing.page),
              children: [
                Text(l10n.structuredCatalogIntro),
                const SizedBox(height: NoWaveSpacing.medium),
                if (_loading)
                  Semantics(
                    liveRegion: true,
                    child: Text(l10n.structuredCatalogLoading),
                  ),
                if (_failed) ...[
                  Text(l10n.structuredCatalogFailure),
                  TextButton(
                    onPressed: _loading ? null : _refresh,
                    child: Text(l10n.actionRetry),
                  ),
                ],
                if (!_loading && !_failed && _entries.isEmpty)
                  Text(l10n.structuredCatalogEmpty),
                for (final entry in _entries)
                  if (entry.key case final key?)
                    ListTile(
                      title: Text(
                        key.articleId,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${l10n.structuredEdition}: ${contentEditionLabel(l10n, key.locale) ?? key.locale}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _loading || _opening ? null : () => _open(entry),
                    )
                  else
                    ListTile(
                      title: Text(l10n.structuredCatalogDamaged),
                      subtitle: Text(l10n.structuredCatalogDamagedHint),
                    ),
                if (_cursor != null && !_loading && !_failed)
                  TextButton(
                    onPressed: () => _load(reset: false),
                    child: Text(l10n.structuredCatalogMore),
                  ),
              ],
            ),
    );
  }
}

/// A catalog-opened editor must also invalidate if the UI account changes
/// before the network session's identity event arrives.
class _AccountBoundIdentity implements NowaveSessionIdentity {
  const _AccountBoundIdentity({
    required this.inner,
    required this.isCurrent,
    required this.changes,
  });
  final NowaveSessionIdentity inner;
  final bool Function() isCurrent;
  final Stream<void> changes;
  @override
  String? get activeUserId => isCurrent() ? inner.activeUserId : null;
  @override
  String? get accessToken => isCurrent() ? inner.accessToken : null;
  @override
  int get sessionGeneration => inner.sessionGeneration;
  @override
  Stream<void> get identityChanges => changes;
}
