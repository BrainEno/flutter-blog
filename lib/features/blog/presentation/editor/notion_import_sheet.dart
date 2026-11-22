import 'dart:async';
import 'dart:typed_data';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/nowave/transport/api_error.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_file_picker.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Import is separate from the editor's own draft and never changes its text.
///
/// The source is either files chosen on the device - Notion's "Markdown &
/// CSV" export ZIP, `.md` pages, or a no-wave JSON bundle - or pasted text
/// (a page's Markdown or a bundle). Markdown is converted here, the way the
/// no-wave desk converts it; only the resulting bundle is sent, and only
/// for a preview until the author confirms.
class NotionImportSheet extends StatefulWidget {
  const NotionImportSheet({
    super.key,
    required this.repository,
    required this.identity,
    required this.fence,
    required this.userCubit,
    this.onApplyStarted,
    this.pickFiles,
  });
  final NotionImportRepository repository;
  final NowaveSessionIdentity identity;
  final NowaveSessionFence fence;
  final AppUserCubit userCubit;
  final VoidCallback? onApplyStarted;

  /// The file picker; the system document picker when null.
  final NotionImportFilePicker? pickFiles;

  @override
  State<NotionImportSheet> createState() => _NotionImportSheetState();
}

class _NotionImportSheetState extends State<NotionImportSheet> {
  final _input = TextEditingController();
  StreamSubscription<void>? _subscription;
  StreamSubscription<AppUserState>? _userSubscription;
  NotionBundle? _source;
  final Set<int> _selected = {};

  /// What converting Markdown could not carry, shown before the preview.
  List<NotionMarkdownWarning> _warnings = const [];

  /// The chosen file names and how many pages they made, when the source is
  /// files rather than pasted text.
  String? _filesRead;

  /// The export's images the pages use, and which ones each page uses.
  Map<String, NotionLocalImage> _images = const {};
  List<Set<String>> _pageImages = const [];

  /// Uploaded images by content, for this sheet's account: a second preview
  /// - after a selection change, an expired plan or a failed upload - does
  /// not upload an image again.
  final Map<String, String> _uploaded = {};

  /// Upload progress while images are uploaded before a preview.
  (int, int)? _uploading;

  /// Images the media service refused, left out of the last preview.
  List<String> _skippedImages = const [];
  NotionBundle? _snapshot;
  NotionImportReport? _report;
  NotionImportPlan? _plan;
  Timer? _expiryTimer;

  void _discardPlan() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _plan?.discard();
    _plan = null;
  }

  void _watchPlan(NotionImportPlan plan) {
    _plan = plan;
    _expiryTimer = Timer(plan.remaining(), () {
      if (!mounted || !identical(_plan, plan)) return;
      setState(() {
        _discardPlan();
        _snapshot = null;
        _confirming = false;
        _error = context.l10n.notionImportPlanInvalid;
      });
    });
  }

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
      _discardPlan();
      _input.clear();
      // The uploaded addresses belong to the account that uploaded them.
      _uploaded.clear();
      if (mounted) {
        setState(() {
          _source = null;
          _selected.clear();
          _warnings = const [];
          _filesRead = null;
          _images = const {};
          _pageImages = const [];
          _skippedImages = const [];
          _snapshot = null;
          _report = null;
          _error = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _discardPlan();
    unawaited(_subscription?.cancel());
    unawaited(_userSubscription?.cancel());
    _input.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _discardPlan();
    setState(() {
      _source = null;
      _selected.clear();
      _warnings = const [];
      _filesRead = null;
      _images = const {};
      _pageImages = const [];
      _skippedImages = const [];
      _snapshot = null;
      _report = null;
      _error = null;
      _confirming = false;
    });
  }

  void _readBundle() {
    if (!_current || _busy) return;
    _discardPlan();
    try {
      _show(readPastedNotionText(_input.text));
    } on NotionImportSourceException catch (error) {
      _fail(switch (error.error) {
        NotionImportSourceError.invalidBundle ||
        NotionImportSourceError.noPages => context.l10n.notionImportInvalid,
        _ => _sourceError(context.l10n, error),
      });
    }
  }

  /// Files chosen on the device: read, converted, and shown for selection.
  /// The pasted text is cleared - one source at a time.
  Future<void> _chooseFiles() async {
    if (!_current || _busy) return;
    final List<NotionImportFile>? files;
    try {
      files = await (widget.pickFiles ?? pickNotionImportFiles)();
    } on NotionImportSourceException catch (error) {
      if (mounted && _current) _fail(_sourceError(context.l10n, error));
      return;
    } catch (_) {
      if (mounted && _current) {
        _fail(context.l10n.notionImportSourceUnreadable);
      }
      return;
    }
    if (!mounted || !_current || files == null || files.isEmpty) return;
    _discardPlan();
    _input.clear();
    try {
      final source = readNotionImportFiles(files);
      _show(
        source,
        filesRead: context.l10n.notionImportFilesRead(
          files.map((file) => file.name).join(', '),
          source.bundle.pageCount,
        ),
      );
    } on NotionImportSourceException catch (error) {
      _fail(_sourceError(context.l10n, error));
    }
  }

  /// Every page starts selected, as on the web: importing an export is the
  /// usual intent, and the author unticks what should stay behind.
  void _show(NotionImportSource source, {String? filesRead}) {
    final bundle = source.bundle;
    setState(() {
      _source = bundle;
      _selected
        ..clear()
        ..addAll({for (var i = 0; i < bundle.pageCount; i++) i});
      _warnings = source.warnings;
      _filesRead = filesRead;
      _images = source.images;
      _pageImages = [
        for (var i = 0; i < bundle.pageCount; i++)
          {
            for (final block
                in ((bundle.json['pages'] as List)[i] as Map)['blocks'] as List)
              if (notionLocalImageKey(block) case final key?) key,
          },
      ];
      _skippedImages = const [];
      _snapshot = null;
      _report = null;
      _error = null;
      _confirming = false;
    });
  }

  void _fail(String message) {
    setState(() {
      _source = null;
      _selected.clear();
      _warnings = const [];
      _filesRead = null;
      _images = const {};
      _pageImages = const [];
      _skippedImages = const [];
      _error = message;
      _report = null;
      _snapshot = null;
      _confirming = false;
    });
  }

  void _setSelection(Set<int> selection) {
    if (!_current || _busy) return;
    _discardPlan();
    setState(() {
      _selected
        ..clear()
        ..addAll(selection);
      _skippedImages = const [];
      _snapshot = null;
      _report = null;
      _error = null;
      _confirming = false;
    });
  }

  /// The local images the selected pages use.
  Set<String> get _selectedImages => {
    for (final index in _selected)
      if (index < _pageImages.length) ..._pageImages[index],
  };

  Future<void> _preview() async {
    final source = _source;
    if (!_current || _busy || source == null || _selected.isEmpty) return;
    var bundle = source.selectPages(_selected);
    final keys = notionLocalImageKeys(bundle);
    if (keys.isNotEmpty) {
      final urls = await _uploadImages(keys);
      if (urls == null || !mounted || !_current) return;
      bundle = withNotionLocalImages(bundle, urls);
    }
    await _submit(bundle, apply: false);
  }

  /// Uploads the images [keys] name, one at a time, and returns their
  /// addresses; an image the media service refuses is left out and named.
  /// Null when the upload stops: a lost connection, a rate limit or a
  /// session change. What was uploaded stays known, so trying again uploads
  /// only the rest.
  Future<Map<String, String>?> _uploadImages(List<String> keys) async {
    final l10n = context.l10n;
    if (keys.length > AppLimits.notionImportMaxImages) {
      setState(() {
        _error = l10n.notionImportTooManyImages(
          keys.length,
          AppLimits.notionImportMaxImages,
        );
      });
      return null;
    }
    _discardPlan();
    setState(() {
      _busy = true;
      _error = null;
      _report = null;
      _snapshot = null;
      _confirming = false;
      _skippedImages = const [];
      _uploading = (0, keys.length);
    });
    final urls = <String, String>{};
    final skipped = <String>[];
    String? stopped;
    for (final (index, key) in keys.indexed) {
      final image = _images[key];
      final name = key.split('/').last;
      final bytes = _readImage(image);
      final type = bytes == null ? null : notionUploadableImageType(bytes);
      if (bytes == null || type == null) {
        skipped.add(name);
      } else {
        final content = _contentKey(name, bytes);
        var url = _uploaded[content];
        if (url == null) {
          final result = await widget.repository.uploadImage(
            bytes: bytes,
            contentType: type,
            sessionFence: widget.fence,
          );
          if (!mounted || !_current) return null;
          final failure = result.fold<Failure?>((f) => f, (_) => null);
          if (failure?.code == 'server.BAD_USER_INPUT') {
            // An animated or oversized image, say: the rest still go.
            skipped.add(name);
          } else if (failure != null) {
            stopped = failure.code == 'server.RATE_LIMITED'
                ? _rateLimited(l10n, failure)
                : l10n.notionImportImageUploadFailed(
                    localizedFailure(l10n, failure),
                  );
            break;
          } else {
            url = result.getOrElse((_) => '');
            _uploaded[content] = url;
          }
        }
        if (url != null) urls[key] = url;
      }
      setState(() => _uploading = (index + 1, keys.length));
    }
    setState(() {
      _busy = false;
      _uploading = null;
      _error = stopped;
      _skippedImages = stopped == null ? skipped : const [];
    });
    return stopped == null ? urls : null;
  }

  static Uint8List? _readImage(NotionLocalImage? image) {
    if (image == null) return null;
    try {
      return image.read();
    } on NotionImportSourceException {
      return null;
    }
  }

  /// Name, size and a 32-bit FNV-1a hash of the bytes: enough to know an
  /// image already uploaded in this sheet, among at most a few dozen.
  static String _contentKey(String name, Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '$name:${bytes.length}:$hash';
  }

  Future<void> _submit(NotionBundle bundle, {required bool apply}) async {
    if (!_current || _busy) return;
    final plan = apply ? _plan : null;
    if (apply &&
        (plan == null || !plan.usable(bundle: bundle, fence: widget.fence))) {
      _discardPlan();
      setState(() {
        _snapshot = null;
        _confirming = false;
        _error = context.l10n.notionImportPlanInvalid;
      });
      return;
    }
    if (!apply) _discardPlan();
    if (apply) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _plan = null;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirming = false;
      if (!apply) {
        // A new preview replaces the old plan, even while the request is pending.
        _report = null;
        _snapshot = null;
      }
    });
    if (apply) widget.onApplyStarted?.call();
    final result = await widget.repository.submit(
      bundle: bundle,
      apply: apply,
      sessionFence: widget.fence,
      plan: plan,
    );
    plan?.discard();
    if (!mounted || !_current) {
      result.fold<void>((_) {}, (report) {
        report.plan?.discard();
      });
      return;
    }
    setState(() {
      _busy = false;
      result.fold(
        (failure) {
          _report = null;
          _snapshot = null;
          // A timeout, invalid response or connection loss cannot prove that a
          // server-side apply did not land; require a fresh preview.
          _error = failure.code == 'notion.planInvalid'
              ? context.l10n.notionImportPlanInvalid
              : failure.code == 'server.RATE_LIMITED'
              ? _rateLimited(context.l10n, failure)
              : apply
              ? context.l10n.notionImportOutcomeUnknown
              : localizedFailure(context.l10n, failure);
        },
        (report) {
          if (report.applied != apply ||
              (!apply &&
                  (report.plan == null ||
                      !report.plan!.usable(
                        bundle: bundle,
                        fence: widget.fence,
                      )))) {
            report.plan?.discard();
            _report = null;
            _snapshot = null;
            _error = apply
                ? context.l10n.notionImportOutcomeUnknown
                : context.l10n.notionImportInvalidReport;
          } else {
            _report = report;
            _snapshot = apply ? null : bundle;
            if (!apply) _watchPlan(report.plan!);
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
                            const SizedBox(height: NoWaveSpacing.small),
                            Text(
                              l10n.notionImportExportHint,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: NoWaveSpacing.medium),
                            FilledButton.tonalIcon(
                              key: const ValueKey('notion-import-choose'),
                              onPressed: _busy ? null : _chooseFiles,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(l10n.notionImportChooseFiles),
                            ),
                            const SizedBox(height: NoWaveSpacing.large),
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
                            if (source != null && _filesRead != null) ...[
                              const SizedBox(height: NoWaveSpacing.medium),
                              Text(
                                _filesRead!,
                                key: const ValueKey('notion-import-files'),
                              ),
                            ],
                            if (source != null && _warnings.isNotEmpty) ...[
                              const SizedBox(height: NoWaveSpacing.medium),
                              _ConversionWarnings(warnings: _warnings),
                            ],
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
                              if (_selectedImages.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: NoWaveSpacing.small,
                                  ),
                                  child: Text(
                                    l10n.notionImportImagesNote(
                                      _selectedImages.length,
                                    ),
                                    key: const ValueKey('notion-import-images'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
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
                                label: switch (_uploading) {
                                  (final done, final total) =>
                                    l10n.notionImportUploadingImages(
                                      done,
                                      total,
                                    ),
                                  null => l10n.notionImportLoading,
                                },
                                compact: true,
                              ),
                            ],
                            if (_skippedImages.isNotEmpty) ...[
                              const SizedBox(height: NoWaveSpacing.small),
                              Text(
                                l10n.notionImportImagesSkipped(
                                  _skippedImages.length,
                                  _skippedImages.join(', '),
                                ),
                                key: const ValueKey('notion-import-skipped'),
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
                                _ReportIssues(issues: page.issues),
                              ],
                              if (report.canApply &&
                                  _snapshot != null &&
                                  _plan != null) ...[
                                const SizedBox(height: NoWaveSpacing.medium),
                                Text(l10n.notionImportWarning),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(l10n.notionImportVersionWarning),
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _preview,
                                  child: Text(l10n.notionImportRefreshPreview),
                                ),
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

/// A 429 is refused before any work, so even an apply is known not to have
/// landed. The server's Retry-After, when sent, says how long to wait.
String _rateLimited(AppLocalizations l10n, Failure failure) {
  final cause = failure.cause;
  final seconds = cause is NowaveApiException ? cause.retryAfterSeconds : null;
  if (seconds == null || seconds <= 0) return l10n.notionImportRateLimited;
  return l10n.notionImportRateLimitedRetry(
    (seconds / Duration.secondsPerMinute).ceil(),
  );
}

String _sourceError(AppLocalizations l10n, NotionImportSourceException error) {
  final name = error.name.isEmpty ? l10n.notionImportChosenFile : error.name;
  return switch (error.error) {
    NotionImportSourceError.tooLarge => l10n.notionImportSourceTooLarge,
    NotionImportSourceError.unsupportedFile =>
      l10n.notionImportSourceUnsupported(name),
    NotionImportSourceError.invalidBundle =>
      l10n.notionImportSourceInvalidBundle(name),
    NotionImportSourceError.invalidZip => l10n.notionImportSourceInvalidZip(
      name,
    ),
    NotionImportSourceError.tooManyEntries =>
      l10n.notionImportSourceTooManyEntries(name),
    NotionImportSourceError.tooManyPages => l10n.notionImportSourceTooManyPages,
    NotionImportSourceError.invalidText => l10n.notionImportSourceInvalidText(
      name,
    ),
    NotionImportSourceError.duplicatePage => l10n.notionImportSourceDuplicate(
      name,
    ),
    NotionImportSourceError.noPages => l10n.notionImportSourceNoPages,
    NotionImportSourceError.csvOnly => l10n.notionImportSourceCsvOnly,
  };
}

/// The conversion's warnings, one line per kind: a 200-page export that
/// lacks page IDs says so once, with a count and the first few files, not
/// two hundred times.
class _ConversionWarnings extends StatelessWidget {
  const _ConversionWarnings({required this.warnings});

  final List<NotionMarkdownWarning> warnings;

  static const _namedFiles = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groups =
        <(NotionMarkdownWarningKind, String, String), List<String>>{};
    for (final warning in warnings) {
      groups
          .putIfAbsent((warning.kind, warning.detail, warning.table), () => [])
          .add(warning.source);
    }
    return Column(
      key: const ValueKey('notion-import-warnings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.notionImportWarningsTitle(warnings.length),
          style: theme.textTheme.titleSmall,
        ),
        for (final MapEntry(key: (kind, detail, table), value: sources)
            in groups.entries) ...[
          const SizedBox(height: NoWaveSpacing.small),
          Text(
            sources.length > 1
                ? '${_message(l10n, kind, detail, table)} '
                      '(${l10n.notionImportWarningCount(sources.length)})'
                : _message(l10n, kind, detail, table),
          ),
          Text(
            _sources(l10n, sources),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  static String _sources(AppLocalizations l10n, List<String> sources) {
    final unique = sources.toSet().toList();
    final named = unique.take(_namedFiles).join(', ');
    return unique.length > _namedFiles
        ? l10n.notionImportWarningSources(named, unique.length - _namedFiles)
        : named;
  }

  static String _message(
    AppLocalizations l10n,
    NotionMarkdownWarningKind kind,
    String detail,
    String table,
  ) => switch (kind) {
    NotionMarkdownWarningKind.missingTitle => l10n.notionImportWarnMissingTitle,
    NotionMarkdownWarningKind.invalidFileName =>
      l10n.notionImportWarnInvalidFileName,
    NotionMarkdownWarningKind.fileNameIdentity =>
      l10n.notionImportWarnFileNameIdentity,
    NotionMarkdownWarningKind.pastedIdentity =>
      l10n.notionImportWarnPastedIdentity,
    NotionMarkdownWarningKind.propertyIgnored =>
      l10n.notionImportWarnPropertyIgnored(detail),
    NotionMarkdownWarningKind.publishedUnrecognized =>
      l10n.notionImportWarnPublished,
    NotionMarkdownWarningKind.titleFromFileName =>
      l10n.notionImportWarnTitleFromFileName(detail),
    NotionMarkdownWarningKind.dateUnrecognized =>
      detail.isEmpty
          ? l10n.notionImportWarnDate
          : l10n.notionImportWarnCsvDate(detail),
    NotionMarkdownWarningKind.dateRange => l10n.notionImportWarnDateRange,
    NotionMarkdownWarningKind.relationUnrecognized =>
      l10n.notionImportWarnRelationUnrecognized(detail),
    NotionMarkdownWarningKind.relationMissing =>
      l10n.notionImportWarnRelationMissing(detail),
    NotionMarkdownWarningKind.inlineImageDropped =>
      l10n.notionImportWarnInlineImage,
    NotionMarkdownWarningKind.relativeLinkDropped =>
      l10n.notionImportWarnRelativeLink,
    NotionMarkdownWarningKind.headingLowered => l10n.notionImportWarnHeading,
    NotionMarkdownWarningKind.codeTooLong => l10n.notionImportWarnCode,
    NotionMarkdownWarningKind.localImageMissing =>
      l10n.notionImportWarnImageMissing(detail),
    NotionMarkdownWarningKind.localImageUnsupported =>
      l10n.notionImportWarnImageUnsupported(detail),
    NotionMarkdownWarningKind.localImageTooLarge =>
      l10n.notionImportWarnImageTooLarge(detail),
    NotionMarkdownWarningKind.signedImageDropped =>
      l10n.notionImportWarnSignedImage,
    NotionMarkdownWarningKind.listSimplified => l10n.notionImportWarnList,
    NotionMarkdownWarningKind.tableFlattened => l10n.notionImportWarnTable,
    NotionMarkdownWarningKind.otherFlattened => l10n.notionImportWarnOther,
    NotionMarkdownWarningKind.csvColumnsIgnored =>
      l10n.notionImportWarnCsvColumns(table, detail),
    NotionMarkdownWarningKind.csvPublishedNotCheckbox =>
      l10n.notionImportWarnCsvPublished(table, detail),
    NotionMarkdownWarningKind.csvNoRow => l10n.notionImportWarnCsvNoRow,
    NotionMarkdownWarningKind.csvAmbiguousRow =>
      l10n.notionImportWarnCsvAmbiguous(detail),
    NotionMarkdownWarningKind.csvFilled => l10n.notionImportWarnCsvFilled(
      table,
      detail,
    ),
    NotionMarkdownWarningKind.csvNothingToFill =>
      l10n.notionImportWarnCsvNothing(table),
    NotionMarkdownWarningKind.csvLocalCover =>
      l10n.notionImportWarnCsvLocalCover,
  };
}

/// A page's report issues in words, one line per kind with a count. The
/// server's detail - a block type, a property - follows in small print; the
/// detail of an expiring image is its signed address and is never shown.
class _ReportIssues extends StatelessWidget {
  const _ReportIssues({required this.issues});

  final List<NotionImportIssue> issues;

  static const _namedDetails = 3;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final groups = <String, List<String>>{};
    for (final issue in issues) {
      final details = groups.putIfAbsent(issue.code, () => []);
      final detail = issue.detail.trim();
      if (issue.code != 'expiring-image-url' && detail.isNotEmpty) {
        details.add(detail);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(key: code, value: details) in groups.entries) ...[
          Text(
            _counted(l10n, code, issues.where((i) => i.code == code).length),
          ),
          if (details.isNotEmpty)
            Text(
              details.toSet().take(_namedDetails).join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ],
    );
  }

  static String _counted(AppLocalizations l10n, String code, int count) {
    final message = notionIssueMessage(l10n, code);
    return count > 1
        ? '$message (${l10n.notionImportWarningCount(count)})'
        : message;
  }
}

/// The words for a server issue code; an unknown code is named, not hidden.
@visibleForTesting
String notionIssueMessage(AppLocalizations l10n, String code) => switch (code) {
  'slug-derived' => l10n.notionImportIssueSlugDerived,
  'empty-block-dropped' => l10n.notionImportIssueEmptyBlock,
  'expiring-image-url' => l10n.notionImportIssueExpiringImage,
  'featured-image-not-carried' => l10n.notionImportIssueFeaturedImage,
  'hierarchy-not-carried' => l10n.notionImportIssueHierarchy,
  'work-type-fallback' => l10n.notionImportIssueWorkTypeFallback,
  'link-block-flattened' => l10n.notionImportIssueLinkBlock,
  'equation-flattened' => l10n.notionImportIssueEquation,
  'callout-flattened' => l10n.notionImportIssueCallout,
  'toggle-flattened' => l10n.notionImportIssueToggle,
  'checkbox-state-dropped' => l10n.notionImportIssueCheckbox,
  'table-block-dropped' => l10n.notionImportIssueTable,
  'unsupported-block' => l10n.notionImportIssueUnsupportedBlock,
  'invalid-block-dropped' => l10n.notionImportIssueInvalidBlock,
  'empty-title' => l10n.notionImportIssueEmptyTitle,
  'empty-body' => l10n.notionImportIssueEmptyBody,
  'image-copy-failed' => l10n.notionImportIssueImageCopyFailed,
  'translation-locale-not-carried' => l10n.notionImportIssueTranslationLocale,
  'work-type-not-carried' => l10n.notionImportIssueWorkType,
  _ => l10n.notionImportIssueOther(code),
};
