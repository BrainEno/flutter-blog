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
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/domain/account_editorial_capacity.dart';
import 'package:belog/features/auth/domain/repository/account_editorial_repository.dart';
import 'package:belog/features/blog/domain/category_paging.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/domain/entities/taxonomy_draft.dart';
import 'package:belog/features/blog/domain/repositories/taxonomy_admin_repository.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

/// Maintaining the category catalogue (#381), for editors only.
///
/// Three facts shape this screen, and none of them can be read off a response:
///
/// - `GET /categories` answers with the names in the *reading* language, while
///   `POST /taxonomies` only accepts the Chinese edition of the catalogue. So a
///   name typed here is stored once and translated nowhere, and the list above
///   may show something else for the same row. The screen says that instead of
///   pretending the two are one field.
/// - The catalogue is one page of [kCategoryListLimit] with no total, so
///   "everything" is never on screen. A full page is said out loud.
/// - A deletion receipt is a boolean: `false` covers both "not yours to
///   delete" and "already gone", and the server does not distinguish them. The
///   app stops at "not removed".
///
/// Nothing here is cached or queued, and no write is replayed. The catalogue is
/// public and shared, so a resend after an unreadable answer is how a duplicate
/// - or a deletion of somebody else's fresh row - gets in.
class TaxonomyAdminPage extends StatefulWidget {
  const TaxonomyAdminPage({
    super.key,
    this.taxonomy,
    this.editorial,
    this.identity,
  });

  /// Test seams, in the shape the shelf screen uses: production resolves these
  /// from the container, a widget test hands in fakes and can then assert the
  /// exact calls - the fence, the body, the row id - rather than only that a
  /// button looked enabled.
  final TaxonomyAdminRepository? taxonomy;
  final AccountEditorialRepository? editorial;
  final NowaveSessionIdentity? identity;

  @override
  State<TaxonomyAdminPage> createState() => _TaxonomyAdminPageState();
}

class _TaxonomyAdminPageState extends State<TaxonomyAdminPage> {
  late final TaxonomyAdminRepository _taxonomy;
  late final AccountEditorialRepository _editorial;
  late final NowaveSessionIdentity _identity;

  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _description = TextEditingController();

  List<CategoryRef> _entries = const [];
  AccountEditorialCapacity _capacity = AccountEditorialCapacity.unknown;
  bool _loading = true;
  bool _busy = false;
  Failure? _failure;
  String? _notice;
  bool _noticeIsError = false;
  int _loadVersion = 0;

  /// The one control whose enabled state is a promise: it only lights up for a
  /// draft this app could also read back.
  static const _addKey = ValueKey('taxonomy-admin-add');

  @override
  void initState() {
    super.initState();
    _taxonomy = widget.taxonomy ?? GetIt.instance<TaxonomyAdminRepository>();
    _editorial =
        widget.editorial ?? GetIt.instance<AccountEditorialRepository>();
    _identity = widget.identity ?? GetIt.instance<NowaveSessionManager>();
    _name.addListener(_onDraftChanged);
    _slug.addListener(_onDraftChanged);
    _description.addListener(_onDraftChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    // In-flight reads compare this counter before touching state, so an answer
    // that lands after the screen is gone cannot reach a dead context.
    _loadVersion++;
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Whether the editor has typed something the catalogue would take. Read on
  /// every keystroke, because a disabled primary button must be explainable.
  void _onDraftChanged() => setState(() {});

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

  TaxonomyDraft get _draft {
    return TaxonomyDraft(
      name: _name.text,
      slug: _slug.text,
      description: _description.text,
    );
  }

  String? get _problem => taxonomyDraftProblem(_draft);

  bool get _canCreate {
    final fence = _fence;
    return fence != null && !_busy && _problem == null;
  }

  /// A form nobody has touched yet is not a draft to be scolded about: the
  /// reason line waits for a keystroke, while the button stays disabled either
  /// way.
  bool get _showReason {
    if (_problem == null) return false;
    return !(_name.text.trim().isEmpty &&
        _slug.text.trim().isEmpty &&
        _description.text.trim().isEmpty);
  }

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
      });
      return;
    }
    // Sequential on purpose, for the reason the shelf screen gives: the role
    // answer has to describe the same session as the catalogue next to it, and
    // two concurrent reads could pair a new role with an old catalogue after an
    // account switch.
    final catalogue = await _taxonomy.catalogue();
    if (!mounted || version != _loadVersion) return;
    final capacity = await _editorial.readCapacity(fence);
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _loading = false;
      catalogue.fold<void>(_rememberFailure, _useCatalogue);
      // A failed role read keeps whatever the entry point already showed: the
      // server refused nobody here, and a lost request is not a "no".
      _capacity = capacity.getOrElse((_) => _capacity);
    });
  }

  void _rememberFailure(Failure failure) {
    _failure = failure;
  }

  void _useCatalogue(List<CategoryRef> entries) {
    _failure = null;
    _entries = entries;
  }

  Future<void> _create() async {
    final fence = _fence;
    if (fence == null || _busy || _problem != null) return;
    final draft = _draft;
    setState(() => _busy = true);
    final result = await _taxonomy.create(fence: fence, draft: draft);
    if (!mounted) return;
    final l10n = context.l10n;
    setState(() {
      _busy = false;
      result.fold<void>(_rememberFailure, (outcome) {
        _failure = null;
        _noticeIsError = outcome != TaxonomyWrite.done;
        _notice = _writeNotice(l10n, outcome, isCreate: true);
        if (outcome == TaxonomyWrite.done) {
          _name.clear();
          _slug.clear();
          _description.clear();
        }
      });
    });
    // Always re-read: the row was just added to a catalogue other editors can
    // write to as well, and the server's answer about it is the only one worth
    // showing.
    await _reload();
  }

  Future<void> _remove(CategoryRef row) async {
    final fence = _fence;
    if (fence == null || _busy) return;
    final l10n = context.l10n;
    final confirmed = await showNoWaveConfirmDialog(
      context,
      title: l10n.taxonomyAdminConfirmTitle,
      message: l10n.taxonomyAdminConfirmMessage,
      cancelLabel: l10n.actionCancel,
      confirmLabel: l10n.taxonomyAdminRemove,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final result = await _taxonomy.remove(fence: fence, id: row.id);
    if (!mounted) return;
    final after = context.l10n;
    setState(() {
      _busy = false;
      result.fold<void>(_rememberFailure, (outcome) {
        _failure = null;
        _noticeIsError = outcome != TaxonomyWrite.done;
        _notice = _writeNotice(after, outcome, isCreate: false);
      });
    });
    await _reload();
  }

  String _writeNotice(
    AppLocalizations l10n,
    TaxonomyWrite outcome, {
    required bool isCreate,
  }) {
    switch (outcome) {
      case TaxonomyWrite.done:
        return isCreate ? l10n.taxonomyAdminAdded : l10n.taxonomyAdminRemoved;
      case TaxonomyWrite.notRemoved:
        return l10n.taxonomyAdminNotRemoved;
      case TaxonomyWrite.refused:
        return l10n.taxonomyAdminRefused;
      case TaxonomyWrite.unavailable:
        return l10n.taxonomyAdminUnavailable;
      case TaxonomyWrite.unknown:
        return l10n.taxonomyAdminUnknownResult;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taxonomyAdminTitle),
        actions: [
          if (_canEdit && !_loading && !_busy)
            IconButton(
              tooltip: l10n.taxonomyAdminRefresh,
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
          return _catalogue(context, l10n);
        },
      ),
    );
  }

  Widget _catalogue(BuildContext context, AppLocalizations l10n) {
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
                Text(l10n.taxonomyAdminDescription),
                const SizedBox(height: NoWaveSpacing.small),
                NoWaveListNote(message: l10n.taxonomyAdminLocaleNote),
                const SizedBox(height: NoWaveSpacing.small),
                NoWaveListNote(message: l10n.taxonomyAdminPageNote),
                if (_entries.length >= kCategoryListLimit) ...[
                  const SizedBox(height: NoWaveSpacing.small),
                  NoWaveListNote(message: l10n.taxonomyAdminPageFull),
                ],
                if (_capacity == AccountEditorialCapacity.unknown) ...[
                  const SizedBox(height: NoWaveSpacing.small),
                  NoWaveListNote(message: l10n.taxonomyAdminUnknownRoleNote),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: NoWaveSpacing.small),
                  _Notice(text: _notice!, isError: _noticeIsError),
                ],
                const SizedBox(height: NoWaveSpacing.large),
                if (_entries.isEmpty)
                  NoWaveStatus(
                    message: l10n.taxonomyAdminEmpty,
                    detail: l10n.taxonomyAdminEmptyDetail,
                  )
                else
                  for (final row in _entries)
                    _CatalogueRow(
                      row: row,
                      busy: _busy,
                      onRemove: () => unawaited(_remove(row)),
                    ),
                const SizedBox(height: NoWaveSpacing.large),
                _addForm(context, l10n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _addForm(BuildContext context, AppLocalizations l10n) {
    final problem = _problem;
    final reason = switch (problem) {
      'taxonomy.nameBlank' => l10n.taxonomyAdminNameBlank,
      'taxonomy.slugUnreadable' => l10n.taxonomyAdminSlugUnreadable,
      'taxonomy.descriptionTooLong' => l10n.taxonomyAdminDescriptionTooLong,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.taxonomyAdminAddTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        TextField(
          key: const ValueKey('taxonomy-admin-name'),
          decoration: InputDecoration(labelText: l10n.taxonomyAdminNameLabel),
          controller: _name,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        TextField(
          key: const ValueKey('taxonomy-admin-slug'),
          decoration: InputDecoration(labelText: l10n.taxonomyAdminSlugLabel),
          controller: _slug,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        TextField(
          key: const ValueKey('taxonomy-admin-description'),
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.taxonomyAdminDescriptionLabel,
          ),
          controller: _description,
        ),
        const SizedBox(height: NoWaveSpacing.small),
        Text(
          l10n.taxonomyAdminDescriptionCount(
            _description.text.length,
            kTaxonomyDescriptionLimit,
          ),
        ),
        if (_showReason && reason != null) ...[
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            reason,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: NoWaveSpacing.medium),
        NoWaveButton(
          key: _addKey,
          label: _busy ? l10n.taxonomyAdminAdding : l10n.taxonomyAdminAdd,
          onPressed: _canCreate ? _create : null,
        ),
      ],
    );
  }
}

/// One catalogue row: the name readers see, the address it lives at, and the
/// single move that takes it away.
///
/// No rename here on purpose. `POST /taxonomies` creates and
/// `DELETE /taxonomies/:id` removes; the backend exposes no per-row update for
/// this list, so an editable field would be a control with no request.
class _CatalogueRow extends StatelessWidget {
  const _CatalogueRow({
    required this.row,
    required this.busy,
    required this.onRemove,
  });

  final CategoryRef row;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // `CategoryRef.id` documents an empty value as "the response did not carry
    // one", and the id is the only thing a delete addresses. Showing the row is
    // still right - the name is real - but the control must not pretend.
    final canRemove = !busy && row.id.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: NoWaveSpacing.small),
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.small),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    row.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: NoWaveSpacing.small),
                  Text(
                    row.slug,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (row.id.isEmpty) ...[
                    const SizedBox(height: NoWaveSpacing.small),
                    NoWaveBadge(label: l10n.taxonomyAdminNoId),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.taxonomyAdminRemove,
              onPressed: canRemove ? onRemove : null,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// One sentence about what the last write did, or could not confirm.
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
