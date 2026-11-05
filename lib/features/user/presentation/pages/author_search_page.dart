import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
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
                24,
                NoWaveSpacing.page,
                16,
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
                      borderSide: BorderSide(color: foreground, width: 2),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: foreground, width: 2),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: AppPalette.orange,
                        width: 3,
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
                CircularProgressIndicator(semanticsLabel: l10n.searching),
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
              AuthorSearchSuccess(:final people) when people.isEmpty => _state(
                NoWaveStatus(message: l10n.authorSearchNoResults),
              ),
              AuthorSearchSuccess(:final people) => SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NoWaveSpacing.page,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final capped = people.length == maxAuthorSearchResults;
                      if (capped && index == 0) {
                        return _contentWidth(
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                l10n.authorSearchLimitNotice,
                                style: NoWaveTypography.meta(context),
                              ),
                            ),
                          ),
                        );
                      }
                      final person = people[index - (capped ? 1 : 0)];
                      return _contentWidth(_AuthorRow(person: person));
                    },
                    childCount:
                        people.length +
                        (people.length == maxAuthorSearchResults ? 1 : 0),
                  ),
                ),
              ),
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NoWaveAvatar(
                    name: name,
                    imageUrl: person.avatarUrl,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
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
                          const SizedBox(height: 4),
                          Text(
                            person.bio,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
