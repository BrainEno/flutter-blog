import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/display_name_l10n.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/presentation/bloc/author_search/author_search_cubit.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

const Duration _searchDebounce = Duration(milliseconds: 300);

/// Public author discovery, scoped to the search tab and kept in memory only.
class AuthorSearchPage extends StatefulWidget {
  const AuthorSearchPage({super.key});

  @override
  State<AuthorSearchPage> createState() => _AuthorSearchPageState();
}

class _AuthorSearchPageState extends State<AuthorSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // An empty field is the browsable directory, not an empty screen. The
    // cubit holds the list, so coming back to this route does not refetch.
    context.read<AuthorSearchCubit>().loadDirectory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String input) {
    _debounce?.cancel();
    setState(() {});
    final cubit = context.read<AuthorSearchCubit>();
    cubit.queryChanged(input);
    final query = input.trim();
    if (!isValidAuthorSearchQuery(query)) return;
    _debounce = Timer(_searchDebounce, () {
      if (mounted) cubit.search(query);
    });
  }

  void _submit(String input) {
    _debounce?.cancel();
    context.read<AuthorSearchCubit>().search(input);
  }

  void _clear() {
    _controller.clear();
    // TextField.onChanged is not called for programmatic controller edits.
    _onChanged('');
  }

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );

  Widget _state(Widget child) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        child: _contentWidth(child),
      ),
    ),
  );

  /// The directory and a query result are the same endpoint and page the same
  /// way; the directory additionally carries a line explaining its order.
  Widget _peopleList(BuildContext context, AuthorSearchList list) {
    final l10n = context.l10n;
    final header = list is AuthorSearchDirectory ? 1 : 0;
    final footer = _hasFooter(list) ? 1 : 0;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.page),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (header == 1 && index == 0) {
            return _contentWidth(
              Padding(
                padding: const EdgeInsets.only(bottom: NoWaveSpacing.medium),
                child: Text(
                  l10n.authorDirectoryDescription,
                  style: NoWaveTypography.meta(context),
                ),
              ),
            );
          }
          final row = index - header;
          if (row == list.people.length) {
            return _contentWidth(_peopleFooter(context, list));
          }
          return _contentWidth(_AuthorRow(person: list.people[row]));
        }, childCount: header + list.people.length + footer),
      ),
    );
  }

  bool _hasFooter(AuthorSearchList list) =>
      list.isLoadingMore || list.loadMoreFailure != null || list.hasMore;

  Widget _peopleFooter(BuildContext context, AuthorSearchList list) {
    final l10n = context.l10n;
    if (list.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Center(
          child: NoWaveLoadingLabel(
            semanticLabel: l10n.loadingMoreAuthors,
            compact: true,
          ),
        ),
      );
    }
    final failure = list.loadMoreFailure;
    if (failure != null) {
      return Column(
        children: [
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            localizedFailure(l10n, failure),
            textAlign: TextAlign.center,
            style: NoWaveTypography.meta(context),
          ),
          TextButton(
            onPressed: () => context.read<AuthorSearchCubit>().loadMore(),
            child: Text(l10n.actionRetry),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NoWaveSpacing.small),
      child: Center(
        child: TextButton(
          onPressed: () => context.read<AuthorSearchCubit>().loadMore(),
          child: Text(l10n.authorDirectoryLoadMore),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.authorSearchTitle)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.page,
                NoWaveSpacing.large,
                NoWaveSpacing.page,
                NoWaveSpacing.medium,
              ),
              child: _contentWidth(
                TextField(
                  controller: _controller,
                  maxLength: maxAuthorSearchQueryLength,
                  // Do not turn a pasted long input into a different query.
                  // Grapheme counts also differ from the API's UTF-16 limit;
                  // queryChanged validates the actual unmodified string.
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  style: NoWaveTypography.title(context, size: 24),
                  decoration: InputDecoration(
                    labelText: l10n.authorSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.clearSearch,
                            icon: const Icon(Icons.clear),
                            onPressed: _clear,
                          ),
                    counterText: '',
                    filled: false,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: foreground,
                        width: NoWaveStroke.focus,
                      ),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: foreground,
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
              ),
            ),
          ),
          BlocBuilder<AuthorSearchCubit, AuthorSearchState>(
            builder: (context, state) => switch (state) {
              AuthorSearchInitial() => _state(
                NoWaveStatus(message: l10n.authorSearchInitial),
              ),
              AuthorSearchLoading() => _state(
                NoWaveLoadingLabel(semanticLabel: l10n.searching),
              ),
              AuthorSearchQueryTooLong() => _state(
                NoWaveStatus(message: l10n.authorSearchTooLong),
              ),
              AuthorSearchFailure(:final failure) => _state(
                NoWaveStatus(
                  message: l10n.searchFailed(localizedFailure(l10n, failure)),
                  actionLabel: l10n.actionRetry,
                  onAction: () => _submit(_controller.text),
                ),
              ),
              AuthorSearchDirectory(:final people) when people.isEmpty =>
                _state(NoWaveStatus(message: l10n.authorDirectoryEmpty)),
              AuthorSearchSuccess(:final people) when people.isEmpty => _state(
                NoWaveStatus(message: l10n.authorSearchNoResults),
              ),
              AuthorSearchList list => _peopleList(context, list),
            },
          ),
        ],
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.person});

  final AuthorSearchResult person;

  @override
  Widget build(BuildContext context) {
    final name = authorDisplayName(context.l10n, person.displayName);
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push(
              shellBranchLocation(
                GoRouterState.of(context).uri,
                '/author/${Uri.encodeComponent(person.userId)}',
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: NoWaveSpacing.small,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The directory returns no avatar: it depends on the reader
                  // in a way this response deliberately does not, so the
                  // initial carries the row.
                  NoWaveAvatar(name: name, size: 48),
                  const SizedBox(width: NoWaveSpacing.small),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.title(context, size: 20),
                        ),
                        if (person.bio.trim().isNotEmpty) ...[
                          const SizedBox(height: NoWaveSpacing.xs),
                          Text(
                            person.bio,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: NoWaveSpacing.xs),
                        // Reach is why the directory is ordered the way it is;
                        // showing it makes the order explicable.
                        Text(
                          context.l10n.authorDirectoryStats(
                            person.workCount,
                            person.followerCount,
                          ),
                          style: NoWaveTypography.meta(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NoWaveSpacing.small),
                  const ExcludeSemantics(child: Icon(Icons.chevron_right)),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
