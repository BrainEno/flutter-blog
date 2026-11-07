import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/router/app_router.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// The device-local reading history of the signed-in account (issue #22).
///
/// Everything shown lives in SQLite and never leaves the device. The list
/// refreshes when the viewer above it pops (a re-read bumps the entry to
/// the top) and each row can be removed individually or wholesale.
class ReadingHistoryPage extends StatefulWidget {
  /// Injectable for tests; resolved from the service locator when absent.
  final ReadingHistoryStore? store;
  const ReadingHistoryPage({super.key, this.store});

  @override
  State<ReadingHistoryPage> createState() => _ReadingHistoryPageState();
}

class _ReadingHistoryPageState extends State<ReadingHistoryPage>
    with RouteAware {
  late final ReadingHistoryStore _store;
  List<ReadingHistoryEntry> _entries = [];
  String? _entriesUserId;
  int _loadVersion = 0;
  int _accountVersion = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? GetIt.instance<ReadingHistoryStore>();
    _entriesUserId = _userId;
    if (_entriesUserId == null) {
      _loading = false;
    } else {
      unawaited(_reload());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      profileRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    profileRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returning from the viewer: the just-read article moved to the top.
    _reload();
  }

  String? _idFor(AppUserState state) =>
      state is AppUserLoggedIn && state.user.id.isNotEmpty
      ? state.user.id
      : null;

  String? get _userId => _idFor(context.read<AppUserCubit>().state);

  void _onAccountChanged(BuildContext _, AppUserState state) {
    final userId = _idFor(state);
    if (userId == _entriesUserId) return;
    _loadVersion++;
    _accountVersion++;
    setState(() {
      _entriesUserId = userId;
      _entries = [];
      _loading = userId != null;
    });
    if (userId != null) unawaited(_reload());
  }

  Future<void> _reload() async {
    final userId = _userId;
    final version = ++_loadVersion;
    if (userId == null) return;
    if (_entriesUserId != userId) {
      setState(() {
        _entriesUserId = userId;
        _entries = [];
        _loading = true;
      });
    }
    try {
      final entries = await _store.list(userId: userId);
      if (!mounted || _userId != userId || version != _loadVersion) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      // Local bookkeeping: never display another account's stale result.
      if (!mounted || _userId != userId || version != _loadVersion) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _remove(ReadingHistoryEntry entry) async {
    final userId = _userId;
    if (userId == null || userId != _entriesUserId) return;
    setState(() => _entries.removeWhere((e) => e.blogId == entry.blogId));
    try {
      await _store.remove(userId: userId, blogId: entry.blogId);
    } catch (_) {
      if (mounted && _userId == userId) await _reload();
    }
  }

  Future<void> _confirmClearAll() async {
    final userId = _userId;
    if (userId == null || userId != _entriesUserId) return;
    final version = _accountVersion;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.clearHistoryTitle,
      message: l10n.clearHistoryBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.actionClear,
    );
    if (!confirmed ||
        !mounted ||
        _userId != userId ||
        version != _accountVersion) {
      return;
    }
    try {
      await _store.clear(userId: userId);
      if (mounted && _userId == userId && version == _accountVersion) {
        // Ignore any list load that began before the clear completed.
        _loadVersion++;
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _userId == userId && version == _accountVersion) {
        await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<AppUserCubit, AppUserState>(
        listener: _onAccountChanged,
        child: _buildScaffold(context),
      );

  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Every colour below comes from the theme palette (issue #24): the
    // earlier hardcoded greys/reds were tuned for one brightness and could
    // drop below the contrast budget in the other.
    final mutedColor = scheme.onSurfaceVariant;
    final userId = _userId;
    final ownerMatches = userId != null && userId == _entriesUserId;
    final entries = ownerMatches ? _entries : <ReadingHistoryEntry>[];
    final loading = userId != null && (!ownerMatches || _loading);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(context.l10n.historyTitle),
        elevation: 1.0,
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clearHistoryTitle,
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: loading
          ? Center(
              child: CircularProgressIndicator(
                semanticsLabel: context.l10n.loading,
              ),
            )
          : entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: mutedColor),
                  const SizedBox(height: NoWaveSpacing.small),
                  Text(
                    context.l10n.historyEmpty,
                    style: TextStyle(fontSize: 16, color: mutedColor),
                  ),
                  const SizedBox(height: NoWaveSpacing.xs),
                  Text(
                    context.l10n.historyEmptyHint,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final readAtLabel = formatDate(
                  Localizations.localeOf(context),
                  entry.readAt,
                );
                return Dismissible(
                  key: ValueKey(entry.blogId),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _remove(entry),
                  background: Container(
                    color: scheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: NoWaveSpacing.medium),
                    child: Icon(Icons.delete, color: scheme.onError),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: NoWaveSpacing.medium,
                      vertical: NoWaveSpacing.xs,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Semantics(
                        image: true,
                        label: context.l10n.coverOf(entry.title),
                        child: SizedBox.square(
                          dimension: NoWaveSizes.listThumbnail,
                          child: entry.imageUrl.isEmpty
                              ? Icon(Icons.article, size: 32, color: mutedColor)
                              : CachedNetworkImage(
                                  imageUrl: entry.imageUrl,
                                  fit: BoxFit.cover,
                                  width: 56,
                                  height: 56,
                                  errorWidget: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.broken_image,
                                        size: 32,
                                        color: mutedColor,
                                      ),
                                ),
                        ),
                      ),
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      entry.posterName.isEmpty
                          ? readAtLabel
                          : '${entry.posterName} · $readAtLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: context.l10n.removeHistoryEntry,
                      icon: Icon(Icons.close, size: 20, color: mutedColor),
                      onPressed: () => _remove(entry),
                    ),
                    onTap: () => context.push('/view/${entry.blogId}'),
                  ),
                );
              },
            ),
    );
  }
}
