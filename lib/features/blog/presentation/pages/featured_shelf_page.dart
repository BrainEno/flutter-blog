import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_badge.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/components/no_wave_list_note.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:belog/features/blog/domain/entities/featured_shelf_entry.dart';
import 'package:belog/features/blog/domain/repositories/featured_shelf_repository.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

/// Arranging the featured shelf (#377): an editorial-only, whole-list write.
///
/// This is not the home tab's list made draggable. The server keeps one shelf
/// per content locale, accepts at most [kFeaturedShelfCapacity] works, and -
/// the part no screen can infer - a `GET /featured` nobody has curated answers
/// with its own default ranking. So what appears here may be somebody's picks
/// or a word-count fallback, and the two are indistinguishable in the response.
/// The page says that out loud, because saving freezes what is on screen as the
/// editorial answer, and an inert-looking "save" that meant "no changes" would
/// be the first lie this screen told.
class FeaturedShelfPage extends StatefulWidget {
  const FeaturedShelfPage({
    super.key,
    this.shelf,
    this.editorial,
    this.identity,
  });

  /// Test seams, in the shape the sessions page uses: production resolves these
  /// from the container, a widget test hands in fakes and can then assert the
  /// exact calls - the locale, the fence, the body - instead of only that a
  /// button looked enabled.
  final FeaturedShelfRepository? shelf;
  final AccountEditorialRepository? editorial;
  final NowaveSessionIdentity? identity;

  @override
  State<FeaturedShelfPage> createState() => _FeaturedShelfPageState();
}

class _FeaturedShelfPageState extends State<FeaturedShelfPage> {
  late final FeaturedShelfRepository _shelf;
  late final AccountEditorialRepository _editorial;
  late final NowaveSessionIdentity _identity;

  List<FeaturedShelfEntry> _entries = const [];
  List<String> _storedIds = const [];
  List<FeaturedShelfEntry> _candidates = const [];
  AccountEditorialCapacity _capacity = AccountEditorialCapacity.unknown;
  String _query = '';
  bool _loading = true;
  bool _searching = false;
  bool _searched = false;
  bool _saving = false;
  Failure? _failure;
  String? _notice;
  bool _noticeIsError = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _shelf = widget.shelf ?? GetIt.instance<FeaturedShelfRepository>();
    _editorial =
        widget.editorial ?? GetIt.instance<AccountEditorialRepository>();
    _identity = widget.identity ?? GetIt.instance<NowaveSessionManager>();
    unawaited(_reload());
  }

  @override
  void dispose() {
    // In-flight reads check this counter before touching state, so a response
    // that lands after the screen is gone cannot reach a dead context.
    _loadVersion++;
    super.dispose();
  }

  /// The shelf being edited is the one for the content language, not the
  /// interface language: `?locale=` decides which shelf the server replaces.
  String get _locale => ContentLocale.instance.tag;

  NowaveSessionFence? get _fence {
    final userId = _identity.activeUserId;
    final token = _identity.accessToken;
    if (userId == null || userId.isEmpty) return null;
    if (token == null || token.isEmpty) return null;
    return NowaveSessionFence(
      userId: userId,
      generation: _identity.sessionGeneration,
    );
  }

  bool get _canEdit => _fence != null;

  List<String> get _ids => [for (final entry in _entries) entry.articleId];

  bool get _dirty {
    if (_ids.length != _storedIds.length) return true;
    for (var index = 0; index < _ids.length; index++) {
      if (_ids[index] != _storedIds[index]) return true;
    }
    return false;
  }

  String? get _problem => featuredShelfProblem(_ids);

  Future<void> _reload() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final fence = _fence;
    if (fence == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entries = const [];
        _storedIds = const [];
      });
      return;
    }
    // Sequential on purpose. The role read is what decides whether the caveat
    // line belongs on this answer, so it has to describe the same session that
    // produced it; two concurrent reads could pair a new role with an old
    // shelf after an account switch.
    final shelf = await _shelf.load(locale: _locale);
    if (!mounted || version != _loadVersion) return;
    final capacity = await _editorial.readCapacity(fence);
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _loading = false;
      shelf.fold<void>(_rememberFailure, _useShelf);
      // A failed role read keeps whatever the entry point already showed: the
      // server has refused nobody here, and a lost request is not a "no".
      _capacity = capacity.getOrElse((_) => _capacity);
    });
  }

  void _rememberFailure(Failure failure) {
    _failure = failure;
  }

  void _useShelf(List<FeaturedShelfEntry> entries) {
    _failure = null;
    _entries = entries;
    _storedIds = [for (final entry in entries) entry.articleId];
  }

  Future<void> _search() async {
    final version = _loadVersion;
    setState(() {
      _searching = true;
      _searched = true;
    });
    final result = await _shelf.browse(locale: _locale, query: _query);
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _searching = false;
      result.fold<void>(_rememberFailure, _useCandidates);
    });
  }

  void _useCandidates(List<FeaturedShelfEntry> entries) {
    _failure = null;
    _candidates = entries;
  }

  void _add(FeaturedShelfEntry entry) {
    setState(() {
      _entries = [..._entries, entry];
      _notice = null;
    });
  }

  void _remove(int index) {
    setState(() {
      _entries = [..._entries]..removeAt(index);
      _notice = null;
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _entries.length) return;
    setState(() {
      final next = [..._entries];
      next.insert(target, next.removeAt(index));
      _entries = next;
      _notice = null;
    });
  }

  Future<void> _save() async {
    final fence = _fence;
    if (fence == null || _problem != null || _saving) return;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: context.l10n.featuredShelfConfirmTitle,
      message: context.l10n.featuredShelfConfirmMessage,
      cancelLabel: context.l10n.actionCancel,
      confirmLabel: context.l10n.featuredShelfSave,
    );
    if (!confirmed || !mounted) return;
    // Captured before the request: the answer is compared against what was
    // actually sent, not against a screen the editor may have kept changing.
    final sent = _ids;
    setState(() => _saving = true);
    final result = await _shelf.save(
      fence: fence,
      locale: _locale,
      articleIds: sent,
    );
    if (!mounted) return;
    final l10n = context.l10n;
    setState(() {
      _saving = false;
      result.fold<void>(_rememberFailure, (saved) {
        _failure = null;
        _noticeIsError = saved.outcome != FeaturedShelfSave.stored;
        _notice = _saveNotice(l10n, saved, sent);
      });
    });
    // Always re-read. The shelf is shared between editors, so the order on
    // screen is only worth trusting after the server has said what it stored.
    await _reload();
  }

  String _saveNotice(
    AppLocalizations l10n,
    FeaturedShelfSaveResult result,
    List<String> sent,
  ) {
    switch (result.outcome) {
      case FeaturedShelfSave.refused:
        return l10n.featuredShelfRefused;
      case FeaturedShelfSave.unavailable:
        return l10n.featuredShelfUnavailable;
      case FeaturedShelfSave.unknown:
        return l10n.featuredShelfUnknownResult;
      case FeaturedShelfSave.stored:
        if (result.storedIds.join('\n') != sent.join('\n')) {
          return l10n.featuredShelfChangedElsewhere;
        }
        return l10n.featuredShelfSaved;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.featuredShelfTitle),
        actions: [
          if (_canEdit && !_loading && !_saving)
            IconButton(
              tooltip: l10n.featuredShelfRefresh,
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: BlocBuilder<AppUserCubit, AppUserState>(
        builder: (context, _) {
          if (!_canEdit) {
            return NoWaveStatus(message: l10n.errorNotSignedIn);
          }
          if (_loading) {
            return Center(
              child: NoWaveLoadingLabel(semanticLabel: l10n.loading),
            );
          }
          return _shelfList(context, l10n);
        },
      ),
      bottomNavigationBar: _loading || !_canEdit ? null : _saveBar(l10n),
    );
  }

  Widget _shelfList(BuildContext context, AppLocalizations l10n) {
    final failure = _failure;
    if (failure != null) {
      return NoWaveStatus(
        message: localizedFailure(l10n, failure),
        actionLabel: l10n.actionRetry,
        onAction: _reload,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(NoWaveSpacing.medium),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: NoWaveSizes.contentColumn,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.featuredShelfDescription),
                const SizedBox(height: NoWaveSpacing.small),
                NoWaveListNote(message: l10n.featuredShelfFallbackNote),
                if (_capacity == AccountEditorialCapacity.unknown) ...[
                  const SizedBox(height: NoWaveSpacing.small),
                  NoWaveListNote(message: l10n.featuredShelfUnknownRoleNote),
                ],
                const SizedBox(height: NoWaveSpacing.small),
                Text(
                  l10n.featuredShelfCounter(
                    _entries.length,
                    kFeaturedShelfCapacity,
                  ),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: NoWaveSpacing.small),
                  _Notice(text: _notice!, isError: _noticeIsError),
                ],
                const SizedBox(height: NoWaveSpacing.medium),
                if (_entries.isEmpty)
                  NoWaveStatus(
                    message: l10n.featuredShelfEmpty,
                    detail: l10n.featuredShelfEmptyDetail,
                  )
                else
                  for (var index = 0; index < _entries.length; index++)
                    _ShelfRow(
                      title: _entries[index].title,
                      position: index + 1,
                      total: _entries.length,
                      busy: _saving,
                      onMoveUp: () => _move(index, -1),
                      onMoveDown: () => _move(index, 1),
                      onRemove: () => _remove(index),
                    ),
                const SizedBox(height: NoWaveSpacing.large),
                _browse(context, l10n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _browse(BuildContext context, AppLocalizations l10n) {
    final onShelf = _ids.toSet();
    final canAdd = !_saving && _problem == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.featuredShelfBrowseTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        TextField(
          decoration: InputDecoration(
            labelText: l10n.featuredShelfBrowseHint,
            suffixIcon: IconButton(
              tooltip: l10n.featuredShelfBrowseAction,
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search),
            ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: (value) => _query = value,
          onSubmitted: (value) {
            _query = value;
            unawaited(_search());
          },
        ),
        if (_searching) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          Center(child: NoWaveLoadingLabel(semanticLabel: l10n.loading)),
        ],
        if (!_searching && _searched && _candidates.isEmpty) ...[
          const SizedBox(height: NoWaveSpacing.medium),
          NoWaveStatus(message: l10n.featuredShelfBrowseEmpty),
        ],
        for (final entry in _candidates)
          Padding(
            padding: const EdgeInsets.only(top: NoWaveSpacing.small),
            child: Row(
              children: [
                Expanded(child: Text(entry.title)),
                if (onShelf.contains(entry.articleId))
                  NoWaveBadge(label: l10n.featuredShelfAlreadyOn)
                else
                  NoWaveButton(
                    label: l10n.featuredShelfBrowseAdd,
                    variant: NoWaveButtonVariant.quiet,
                    onPressed: canAdd ? () => _add(entry) : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _saveBar(AppLocalizations l10n) {
    final problem = _problem;
    final reason = switch (problem) {
      'featured.tooMany' => l10n.featuredShelfTooMany(kFeaturedShelfCapacity),
      'featured.duplicate' => l10n.featuredShelfDuplicate,
      _ => null,
    };
    return SafeArea(
      minimum: const EdgeInsets.all(NoWaveSpacing.medium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reason != null)
            Text(
              reason,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          NoWaveButton(
            // The one control whose enabled state is a promise: it only ever
            // lights up for a list that differs from the stored one and that
            // the shelf would accept.
            key: const ValueKey('featured-shelf-save'),
            label: _saving
                ? l10n.featuredShelfSaving
                : l10n.featuredShelfSave,
            onPressed: _dirty && reason == null && !_saving ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// One row of the shelf: where the work sits, and the three moves that change
/// it.
///
/// Up and down instead of a drag handle, for two reasons a whole-list save
/// makes real. A mis-drag here rewrites the shelf for every reader, and a
/// drag-and-drop target the screen reader cannot name is not an affordance -
/// whereas these three buttons each carry a label the reader hears.
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.title,
    required this.position,
    required this.total,
    required this.busy,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final String title;
  final int position;
  final int total;

  /// Disables the moves while the save is in flight, so the list on screen is
  /// the list that was sent.
  final bool busy;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: NoWaveSpacing.small),
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.small),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$position. $title',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: l10n.featuredShelfMoveUp,
              onPressed: busy || position == 1 ? null : onMoveUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: l10n.featuredShelfMoveDown,
              onPressed: busy || position == total ? null : onMoveDown,
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: l10n.featuredShelfRemove,
              onPressed: busy ? null : onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// One sentence about what the last save did, or could not confirm.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: TextStyle(
        color: isError ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );
}
