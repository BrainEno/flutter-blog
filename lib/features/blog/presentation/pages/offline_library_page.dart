import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_section_heading.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/components/no_wave_notice.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library_query.dart';
import 'package:belog/features/blog/presentation/blocs/offline_library/offline_library_cubit.dart';
import 'package:belog/features/blog/presentation/offline_library/offline_library_article_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// A local-only catalog of the active backend/content-language article cache.
///
/// This page deliberately has no account prerequisite: public article cache
/// rows are not an account-scoped saved list, and an anonymous reader should
/// still be able to find an article they previously opened while offline.
/// Every operation goes through [OfflineLibraryCubit], which is deliberately
/// independent from `ConnectionChecker` and cannot create an HTTP request.
class OfflineLibraryPage extends StatefulWidget {
  const OfflineLibraryPage({super.key});

  @override
  State<OfflineLibraryPage> createState() => _OfflineLibraryPageState();
}

class _OfflineLibraryPageState extends State<OfflineLibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  late final OfflineLibraryCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<OfflineLibraryCubit>();
    _searchController.addListener(_onQueryChanged);
    unawaited(_cubit.load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() => _cubit.setQuery(_searchController.text);

  void _clearQuery() => _searchController.clear();

  Future<void> _confirmClear(OfflineLibraryState state) async {
    final snapshot = state.snapshot;
    if (snapshot == null || snapshot.isEmpty || state.isClearing) return;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.offlineLibraryClearTitle,
      message: l10n.offlineLibraryClearBody,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.offlineLibraryClearAction,
    );
    if (!mounted || !confirmed) return;
    await _cubit.clear();
  }

  Future<void> _refresh() => _cubit.load();

  void _open(OfflineLibraryEntry entry) {
    // Pass the exact local model so the viewer can render immediately. It still
    // owns its established normal fetch/cache behaviour if a connection is
    // present; opening one item is the reader's explicit action, unlike merely
    // browsing a library which must not instantiate image/network providers.
    context.push(
      '/search/offline-library/view/${Uri.encodeComponent(entry.article.id)}',
      extra: entry.article,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LocaleBloc, LocaleState>(
      listenWhen: (previous, current) => previous.content != current.content,
      listener: (_, _) => unawaited(_cubit.load()),
      child: BlocConsumer<OfflineLibraryCubit, OfflineLibraryState>(
        listenWhen: (previous, current) =>
            previous.clearFailure != current.clearFailure &&
            current.clearFailure != null,
        listener: (context, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.offlineLibraryClearFailed)),
        ),
        builder: (context, state) => _scaffold(context, state),
      ),
    );
  }

  Widget _scaffold(BuildContext context, OfflineLibraryState state) {
    final snapshot = state.snapshot;
    final canClear = snapshot != null && !snapshot.isEmpty && !state.isClearing;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.offlineLibraryTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.offlineLibraryRefresh,
            onPressed: state.isLoading || state.isClearing ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: context.l10n.offlineLibraryClearTooltip,
            onPressed: canClear ? () => _confirmClear(state) : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: NoWaveSpacing.small),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: _body(context, state)),
    );
  }

  Widget _body(BuildContext context, OfflineLibraryState state) {
    if (state.snapshot == null && state.isLoading) {
      return _singleState(
        context,
        NoWaveLoadingLabel(semanticLabel: context.l10n.offlineLibraryLoading),
      );
    }
    if (state.snapshot == null && state.hasLoadFailure) {
      return _singleState(
        context,
        NoWaveStatus(
          message: context.l10n.offlineLibraryLoadFailed,
          actionLabel: context.l10n.actionRetry,
          onAction: _refresh,
        ),
      );
    }

    final snapshot = state.snapshot;
    if (snapshot == null) {
      // The only remaining state is an immediate build before the first load.
      // It stays scrollable so pull-to-refresh and accessibility work there.
      return _singleState(
        context,
        NoWaveLoadingLabel(semanticLabel: context.l10n.offlineLibraryLoading),
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _contentWidth(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.page,
                NoWaveSpacing.large,
                NoWaveSpacing.page,
                NoWaveSpacing.medium,
              ),
              child: _header(context, state, snapshot),
            ),
          ),
        ),
        ..._resultsSlivers(context, state, snapshot),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    OfflineLibraryState state,
    OfflineLibrarySnapshot snapshot,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoWaveSectionHeading(title: l10n.offlineLibraryTitle),
        const SizedBox(height: NoWaveSpacing.small),
        Text(
          l10n.offlineLibraryDescription,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: NoWaveSpacing.medium),
        NoWaveNotice(
          message: l10n.offlineLibraryScopeHint,
          tone: NoWaveNoticeTone.info,
          icon: Icons.phone_android_outlined,
        ),
        if (state.hasLoadFailure) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          NoWaveNotice(
            message: l10n.offlineLibraryLoadFailed,
            tone: NoWaveNoticeTone.error,
            actionLabel: l10n.actionRetry,
            onAction: _refresh,
            isLive: true,
          ),
        ],
        const SizedBox(height: NoWaveSpacing.medium),
        Semantics(
          container: true,
          child: Wrap(
            spacing: NoWaveSpacing.small,
            runSpacing: NoWaveSpacing.small,
            children: [
              _MetadataPill(
                icon: Icons.language_outlined,
                label: l10n.offlineLibraryScope(snapshot.locale),
              ),
              _MetadataPill(
                icon: Icons.article_outlined,
                label: l10n.offlineLibraryStats(
                  formatNumber(
                    Localizations.localeOf(context),
                    snapshot.summary.articleCount,
                  ),
                  _formatBytes(context, snapshot.summary.estimatedBytes),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NoWaveSpacing.xs),
        Text(
          l10n.offlineLibrarySizeHint,
          style: NoWaveTypography.meta(context),
        ),
        if (snapshot.summary.newestAccessedAt != null) ...[
          const SizedBox(height: NoWaveSpacing.xs),
          Text(
            formatDate(
              Localizations.localeOf(context),
              snapshot.summary.newestAccessedAt!,
            ),
            style: NoWaveTypography.meta(context),
          ),
        ],
        const SizedBox(height: NoWaveSpacing.large),
        TextField(
          controller: _searchController,
          maxLength: OfflineLibraryQuery.maxLength,
          textInputAction: TextInputAction.search,
          style: NoWaveTypography.title(context, size: 24),
          decoration: InputDecoration(
            labelText: l10n.offlineLibrarySearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.clearSearch,
                    icon: const Icon(Icons.clear),
                    onPressed: _clearQuery,
                  ),
            counterText: '',
            filled: false,
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: NoWaveStroke.focus,
              ),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: NoWaveStroke.focus,
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                color: AppPalette.orange,
                width: NoWaveStroke.focus,
              ),
            ),
          ),
        ),
        if (state.isClearing) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          NoWaveLoadingLabel(semanticLabel: l10n.offlineLibraryClearing),
        ],
      ],
    );
  }

  List<Widget> _resultsSlivers(
    BuildContext context,
    OfflineLibraryState state,
    OfflineLibrarySnapshot snapshot,
  ) {
    if (state.hasQuery && state.queryIssue != null) {
      return [
        _statusSliver(context, _queryIssueMessage(context, state.queryIssue!)),
      ];
    }
    if (snapshot.isEmpty) {
      return [
        _statusSliver(
          context,
          context.l10n.offlineLibraryEmpty,
          detail: context.l10n.offlineLibraryEmptyHint,
        ),
      ];
    }
    if (state.hasValidQuery) {
      if (state.results.isEmpty) {
        return [_statusSliver(context, context.l10n.offlineLibraryNoResults)];
      }
      return [
        _entryList(
          context,
          count: state.results.length,
          itemBuilder: (index) => OfflineLibraryArticleTile.search(
            result: state.results[index],
            index: index + 1,
            onTap: () => _open(state.results[index].entry),
          ),
        ),
        if (state.results.length >= OfflineLibraryQuery.maxResults)
          SliverToBoxAdapter(
            child: _contentWidth(
              Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.page),
                child: Text(
                  context.l10n.offlineLibraryResultLimit(
                    formatNumber(
                      Localizations.localeOf(context),
                      OfflineLibraryQuery.maxResults,
                    ),
                  ),
                  textAlign: TextAlign.center,
                  style: NoWaveTypography.meta(context),
                ),
              ),
            ),
          ),
      ];
    }
    return [
      _entryList(
        context,
        count: state.catalogEntries.length,
        itemBuilder: (index) => OfflineLibraryArticleTile.catalog(
          entry: state.catalogEntries[index],
          index: index + 1,
          onTap: () => _open(state.catalogEntries[index]),
        ),
      ),
    ];
  }

  Widget _entryList(
    BuildContext context, {
    required int count,
    required Widget Function(int index) itemBuilder,
  }) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.page),
    sliver: SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _contentWidth(itemBuilder(index)),
        childCount: count,
      ),
    ),
  );

  Widget _statusSliver(
    BuildContext context,
    String message, {
    String? detail,
  }) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        child: _contentWidth(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoWaveStatus(message: message),
              if (detail != null) ...[
                const SizedBox(height: NoWaveSpacing.small),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _singleState(BuildContext context, Widget child) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(NoWaveSpacing.page),
    children: [
      SizedBox(height: NoWaveSizes.emptyStateOffset),
      _contentWidth(Center(child: child)),
    ],
  );

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: NoWaveSizes.maxReadingWidth),
      child: child,
    ),
  );

  String _formatBytes(BuildContext context, int bytes) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context);
    if (bytes < 1024) {
      return l10n.offlineLibrarySizeBytes(formatNumber(locale, bytes));
    }
    final kibibytes = (bytes + 1023) ~/ 1024;
    if (kibibytes < 1024) {
      return l10n.offlineLibrarySizeKiB(formatNumber(locale, kibibytes));
    }
    final mebibytes = (kibibytes + 1023) ~/ 1024;
    return l10n.offlineLibrarySizeMiB(formatNumber(locale, mebibytes));
  }

  String _queryIssueMessage(
    BuildContext context,
    OfflineLibraryQueryIssue issue,
  ) => switch (issue) {
    OfflineLibraryQueryIssue.empty => context.l10n.offlineLibraryNoResults,
    OfflineLibraryQueryIssue.tooLong => context.l10n.offlineLibraryQueryTooLong,
    OfflineLibraryQueryIssue.tooManyTerms =>
      context.l10n.offlineLibraryQueryTooManyTerms,
    OfflineLibraryQueryIssue.termTooLong =>
      context.l10n.offlineLibraryQueryTermTooLong,
    OfflineLibraryQueryIssue.unclosedQuote =>
      context.l10n.offlineLibraryQueryUnclosedQuote,
    OfflineLibraryQueryIssue.invalidQuote =>
      context.l10n.offlineLibraryQueryInvalidQuote,
  };
}

/// A plain metadata chip used only for scope and aggregate cache facts. It is
/// not interactive, so it cannot accidentally look like an online filter.
class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: color.withAlpha(NoWaveOpacity.dividerAlpha),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NoWaveSpacing.small,
            vertical: NoWaveSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: NoWaveIconSize.inline, color: color),
              ),
              const SizedBox(width: NoWaveSpacing.xs),
              Text(
                label,
                style: NoWaveTypography.meta(context).copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
