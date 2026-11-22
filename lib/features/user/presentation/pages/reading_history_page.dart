import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_entrance.dart';
import 'package:belog/core/design/components/no_wave_pressable.dart';
import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/router/app_router.dart';
import 'package:belog/features/blog/domain/entities/reading_stats.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/user/presentation/widgets/reading_stats_card.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:belog/router/route_paths.dart';
import 'package:belog/router/shell_branch_location.dart';

/// The device-local reading history of the signed-in account (issue #22).
///
/// Everything shown lives in SQLite and never leaves the device. The list
/// refreshes when the viewer above it pops (a re-read bumps the entry to
/// the top) and each row can be removed individually or wholesale.
///
/// A [ReadingStatsCard] sits above a non-empty list: counts for the last seven
/// days, the current and longest reading streak, and a seven-day activity
/// strip. It is computed from the rows already loaded, so it updates with
/// every removal or re-read and needs no storage of its own.
class ReadingHistoryPage extends StatefulWidget {
  /// Injectable for tests; resolved from the service locator when absent.
  final ReadingHistoryStore? store;

  /// The clock the reading summary measures "today" with. Injectable so a
  /// test can pin the calendar; production reads the device clock.
  final DateTime Function() clock;

  const ReadingHistoryPage({super.key, this.store, this.clock = DateTime.now});

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
  bool _legacyAvailable = false;
  bool _clearingLegacy = false;
  int _legacyLoadVersion = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? GetIt.instance<ReadingHistoryStore>();
    _entriesUserId = _userId;
    if (_entriesUserId == null) {
      _loading = false;
    } else {
      unawaited(_reload());
      unawaited(_loadLegacyStatus());
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
    _legacyLoadVersion++;
    setState(() {
      _legacyAvailable = false;
      _entriesUserId = userId;
      _entries = [];
      _loading = userId != null;
    });
    if (userId != null) {
      unawaited(_reload());
      unawaited(_loadLegacyStatus());
    }
  }

  Future<void> _loadLegacyStatus() async {
    final store = _store;
    final userId = _userId;
    final version = ++_legacyLoadVersion;
    final accountVersion = _accountVersion;
    if (store is! UnattributedHistoryMaintenance || userId == null) return;
    try {
      final available = await (store as UnattributedHistoryMaintenance)
          .hasUnattributedHistory();
      if (!mounted ||
          _userId != userId ||
          version != _legacyLoadVersion ||
          accountVersion != _accountVersion) {
        return;
      }
      setState(() => _legacyAvailable = available);
    } catch (_) {
      // A failed diagnostic never prevents viewing the current history.
    }
  }

  Future<void> _confirmClearLegacy() async {
    final store = _store;
    final userId = _userId;
    if (store is! UnattributedHistoryMaintenance ||
        userId == null ||
        userId != _entriesUserId ||
        !_legacyAvailable ||
        _clearingLegacy) {
      return;
    }
    final accountVersion = _accountVersion;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.historyLegacyClearTitle,
      message: l10n.historyLegacyClearBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.actionClear,
    );
    if (!mounted ||
        !confirmed ||
        _userId != userId ||
        _accountVersion != accountVersion ||
        _clearingLegacy) {
      return;
    }
    setState(() => _clearingLegacy = true);
    try {
      await (store as UnattributedHistoryMaintenance)
          .clearUnattributedHistory();
      if (!mounted || _userId != userId || _accountVersion != accountVersion) {
        return;
      }
      _legacyLoadVersion++;
      setState(() => _legacyAvailable = false);
    } catch (_) {
      if (mounted && _userId == userId && _accountVersion == accountVersion) {
        showSnackBar(context, context.l10n.errorStorage);
      }
    } finally {
      if (mounted) setState(() => _clearingLegacy = false);
    }
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
    final userId = _userId;
    final ownerMatches = userId != null && userId == _entriesUserId;
    final entries = ownerMatches ? _entries : <ReadingHistoryEntry>[];
    final loading = userId != null && (!ownerMatches || _loading);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.historyTitle),
        actions: [
          if (ownerMatches && _legacyAvailable)
            IconButton(
              tooltip: context.l10n.historyLegacyClearTitle,
              icon: const Icon(Icons.storage_outlined),
              onPressed: _clearingLegacy ? null : _confirmClearLegacy,
            ),
          if (entries.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clearHistoryTitle,
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: loading
          ? NoWaveSkeletonList(semanticLabel: context.l10n.loading)
          : entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                child: NoWaveStatus(
                  message: context.l10n.historyEmpty,
                  detail: context.l10n.historyEmptyHint,
                ),
              ),
            )
          : NoWaveEntranceScope(
              // Another account's history is a new list; a re-read that moves
              // a row to the top is not.
              generation: _entriesUserId,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: NoWaveSpacing.section),
                // Row 0 is the reading summary; history rows follow it.
                itemCount: entries.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ReadingStatsCard(
                      stats: ReadingStats.from(entries, now: widget.clock()),
                    );
                  }
                  final entry = entries[index - 1];
                  return Dismissible(
                    key: ValueKey(entry.blogId),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _remove(entry),
                    background: _SwipeToRemove(
                      label: context.l10n.actionDelete,
                    ),
                    child: NoWaveEntrance(
                      index: index - 1,
                      child: _HistoryRow(
                        entry: entry,
                        onRemove: () => _remove(entry),
                        // Stay on the profile tab's stack so popping the
                        // reader returns here and didPopNext refreshes.
                        onOpen: () => context.push(
                          shellBranchLocation(
                            GoRouterState.of(context).uri,
                            RoutePaths.view(entry.blogId),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// One read, set like a row of the feed (every colour from the theme, issue
/// #24): when it was read, the title in the
/// serif, who wrote it - on a rule, with the press response of an article
/// card. No thumbnail: the history is an index of what was read, and the
/// feed's own rows are type alone, so the two lists now look like one
/// publication.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  final ReadingHistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final readAt = formatDate(locale, entry.readAt);
    // How far the reader got, after the date: a log of what was read says
    // also what was left unfinished.
    final progress = entry.progress;
    final reached = progress == null || progress < ReadingProgress.started
        ? null
        : progress >= ReadingProgress.finished
        ? l10n.historyFinished
        : l10n.historyProgress(formatPercent(locale, progress));
    return NoWavePressable(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.page),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.onSurface.withAlpha(NoWaveOpacity.dividerAlpha),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(
              top: NoWaveSpacing.medium,
              bottom: NoWaveSpacing.medium,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reached == null ? readAt : '$readAt · $reached',
                        style: NoWaveTypography.meta(context),
                      ),
                      const SizedBox(height: NoWaveSpacing.xs),
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // A step under the feed row's 24: a log, not a
                        // front page.
                        style: NoWaveTypography.title(context, size: 20),
                      ),
                      if (entry.posterName.isNotEmpty) ...[
                        const SizedBox(height: NoWaveSpacing.xs),
                        Text(
                          entry.posterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.meta(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: NoWaveSpacing.small),
                IconButton(
                  tooltip: l10n.removeHistoryEntry,
                  icon: Icon(
                    Icons.close,
                    size: NoWaveIconSize.row,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a swipe uncovers: the inverted slip of a snackbar with the word for
/// what letting go does, instead of a red field and a bin icon - removing a
/// line from a private list is not an alarm.
class _SwipeToRemove extends StatelessWidget {
  const _SwipeToRemove({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.inverseSurface,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: NoWaveSpacing.page),
          child: Text(
            label,
            style: NoWaveTypography.metaLabel(
              context,
              color: scheme.onInverseSurface,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
