import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';

import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:flutter/material.dart';

/// Import is separate from the editor's own draft and never changes its text.
class NotionImportSheet extends StatefulWidget {
  const NotionImportSheet({
    super.key,
    required this.repository,
    required this.identity,
    required this.fence,
    required this.userCubit,
    this.onApplyStarted,
  });
  final NotionImportRepository repository;
  final NowaveSessionIdentity identity;
  final NowaveSessionFence fence;
  final AppUserCubit userCubit;
  final VoidCallback? onApplyStarted;

  @override
  State<NotionImportSheet> createState() => _NotionImportSheetState();
}

class _NotionImportSheetState extends State<NotionImportSheet> {
  final _input = TextEditingController();
  StreamSubscription<void>? _subscription;
  StreamSubscription<AppUserState>? _userSubscription;
  NotionBundle? _source;
  final Set<int> _selected = {};
  NotionBundle? _snapshot;
  NotionImportReport? _report;
  String? _error;
  bool _busy = false;
  bool _confirming = false;
  bool _invalidated = false;

  bool get _current =>
      !_invalidated &&
      widget.userCubit.state is AppUserLoggedIn &&
      (widget.userCubit.state as AppUserLoggedIn).user.id ==
          widget.fence.userId &&
      widget.identity.activeUserId == widget.fence.userId &&
      widget.identity.sessionGeneration == widget.fence.generation &&
      (widget.identity.accessToken?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _invalidated = !_current;
    _subscription = widget.identity.identityChanges.listen(
      (_) => _checkIdentity(),
    );
    _userSubscription = widget.userCubit.stream.listen((_) => _checkIdentity());
  }

  void _checkIdentity() {
    if (!_current && !_invalidated) {
      _invalidated = true;
      _input.clear();
      if (mounted) {
        setState(() {
          _source = null;
          _selected.clear();
          _snapshot = null;
          _report = null;
          _error = null;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_userSubscription?.cancel());
    _input.dispose();
    super.dispose();
  }

  void _changed(String _) {
    setState(() {
      _source = null;
      _selected.clear();
      _snapshot = null;
      _report = null;
      _error = null;
      _confirming = false;
    });
  }

  void _readBundle() {
    if (!_current || _busy) return;
    try {
      final bundle = NotionBundle.parse(_input.text);
      setState(() {
        _source = bundle;
        _selected.clear();
        _snapshot = null;
        _report = null;
        _error = null;
        _confirming = false;
      });
    } on FormatException {
      setState(() {
        _source = null;
        _selected.clear();
        _error = context.l10n.notionImportInvalid;
        _report = null;
        _snapshot = null;
        _confirming = false;
      });
    }
  }

  void _setSelection(Set<int> selection) {
    if (!_current || _busy) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(selection);
      _snapshot = null;
      _report = null;
      _error = null;
      _confirming = false;
    });
  }

  Future<void> _preview() async {
    final source = _source;
    if (!_current || _busy || source == null || _selected.isEmpty) return;
    await _submit(source.selectPages(_selected), apply: false);
  }

  Future<void> _submit(NotionBundle bundle, {required bool apply}) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _confirming = false;
    });
    if (apply) widget.onApplyStarted?.call();
    final result = await widget.repository.submit(
      bundle: bundle,
      apply: apply,
      sessionFence: widget.fence,
    );
    if (!mounted || !_current) return;
    setState(() {
      _busy = false;
      result.fold(
        (failure) {
          _report = null;
          _snapshot = null;
          // A timeout, invalid response or connection loss cannot prove that a
          // server-side apply did not land; require a fresh preview.
          _error = apply
              ? context.l10n.notionImportOutcomeUnknown
              : localizedFailure(context.l10n, failure);
        },
        (report) {
          if (report.applied != apply) {
            _report = null;
            _snapshot = null;
            _error = apply
                ? context.l10n.notionImportOutcomeUnknown
                : context.l10n.notionImportInvalidReport;
          } else {
            _report = report;
            _snapshot = apply ? null : bundle;
          }
        },
      );
    });
  }

  String _action(NotionImportAction action) => switch (action) {
    NotionImportAction.create => context.l10n.notionImportCreate,
    NotionImportAction.update => context.l10n.notionImportUpdate,
    NotionImportAction.skip => context.l10n.notionImportSkip,
    NotionImportAction.refused => context.l10n.notionImportRefused,
    NotionImportAction.failed => context.l10n.notionImportFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = _report;
    final source = _source;
    return PopScope(
      canPop: !_busy || !_current,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(NoWaveSpacing.medium),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.notionImportTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: _busy && _current
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: !_current
                    ? Center(child: Text(l10n.editorSessionChanged))
                    : SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          NoWaveSpacing.medium,
                          NoWaveSpacing.medium,
                          NoWaveSpacing.medium,
                          MediaQuery.viewInsetsOf(context).bottom +
                              NoWaveSpacing.medium,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(l10n.notionImportDescription),
                            const SizedBox(height: NoWaveSpacing.medium),
                            TextField(
                              controller: _input,
                              onChanged: _changed,
                              enabled: !_busy,
                              minLines: 4,
                              maxLines: 8,
                              decoration: InputDecoration(
                                labelText: l10n.notionImportInput,
                              ),
                            ),
                            const SizedBox(height: NoWaveSpacing.medium),
                            OutlinedButton(
                              onPressed: _busy ? null : _readBundle,
                              child: Text(l10n.notionImportReadBundle),
                            ),
                            if (source != null) ...[
                              const SizedBox(height: NoWaveSpacing.medium),
                              Text(
                                l10n.notionImportSelectionTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(l10n.notionImportSelectionHint),
                              Text(
                                l10n.notionImportSelectionCount(
                                  _selected.length,
                                  source.pageCount,
                                ),
                              ),
                              if (source.pageCount == 0)
                                Text(l10n.notionImportNoPages),
                              if (source.pageCount > 0) ...[
                                Wrap(
                                  spacing: NoWaveSpacing.small,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          _busy ||
                                              _selected.length ==
                                                  source.pageCount
                                          ? null
                                          : () => _setSelection({
                                              for (
                                                var i = 0;
                                                i < source.pageCount;
                                                i++
                                              )
                                                i,
                                            }),
                                      child: Text(l10n.notionImportSelectAll),
                                    ),
                                    TextButton(
                                      onPressed: _busy || _selected.isEmpty
                                          ? null
                                          : () => _setSelection({}),
                                      child: Text(
                                        l10n.notionImportClearSelection,
                                      ),
                                    ),
                                  ],
                                ),
                                for (
                                  var index = 0;
                                  index < source.pageCount;
                                  index++
                                )
                                  CheckboxListTile(
                                    value: _selected.contains(index),
                                    onChanged: _busy
                                        ? null
                                        : (value) {
                                            final next = Set<int>.of(_selected);
                                            if (value == true) {
                                              next.add(index);
                                            } else {
                                              next.remove(index);
                                            }
                                            _setSelection(next);
                                          },
                                    title: Text(
                                      source.pageTitle(index).isEmpty
                                          ? l10n.notionImportUntitledPage(
                                              index + 1,
                                            )
                                          : source.pageTitle(index),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      l10n.notionImportPageNumber(index + 1),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  ),
                              ],
                              FilledButton(
                                onPressed: _busy || _selected.isEmpty
                                    ? null
                                    : _preview,
                                child: Text(l10n.notionImportPreviewSelected),
                              ),
                            ],
                            if (_busy) ...[
                              const SizedBox(height: NoWaveSpacing.small),
                              NoWaveLoadingLabel(
                                label: l10n.notionImportLoading,
                                compact: true,
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: NoWaveSpacing.medium),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            if (report != null) ...[
                              const SizedBox(height: NoWaveSpacing.large),
                              Text(
                                report.applied
                                    ? l10n.notionImportResult
                                    : l10n.notionImportPlan,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                l10n.notionImportSummary(
                                  report.count(NotionImportAction.create),
                                  report.count(NotionImportAction.update),
                                  report.count(NotionImportAction.skip),
                                  report.count(NotionImportAction.refused),
                                  report.count(NotionImportAction.failed),
                                ),
                              ),
                              if (report.omittedPages > 0)
                                Text(
                                  l10n.notionImportOmitted(report.omittedPages),
                                ),
                              for (final page in report.pages) ...[
                                const Divider(),
                                Text(
                                  '${_action(page.action)} · ${page.title} (${page.locale})',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if (page.detail.isNotEmpty) Text(page.detail),
                                if (page.slug.isNotEmpty)
                                  Text(
                                    '${l10n.notionImportSlug}: ${page.slug}',
                                  ),
                                if (page.articleId != null)
                                  Text(
                                    '${l10n.notionImportArticleId}: ${page.articleId}',
                                  ),
                                for (final issue in page.issues)
                                  Text(
                                    issue.code == 'expiring-image-url'
                                        ? issue.code
                                        : '${issue.code}: ${issue.detail}',
                                  ),
                              ],
                              if (report.canApply && _snapshot != null) ...[
                                const SizedBox(height: NoWaveSpacing.medium),
                                Text(l10n.notionImportWarning),
                                if (!_confirming)
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _confirming = true,
                                          ),
                                    child: Text(l10n.notionImportReviewConfirm),
                                  )
                                else ...[
                                  Text(l10n.notionImportConfirmPrompt),
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                              _submit(_snapshot!, apply: true),
                                    child: Text(l10n.notionImportConfirm),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _confirming = false,
                                          ),
                                    child: Text(l10n.actionCancel),
                                  ),
                                ],
                              ],
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
