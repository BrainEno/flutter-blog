import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_import/notion_image_upload.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_plan.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:belog/features/blog/domain/notion_import/notion_local_images.dart';
import 'package:belog/features/blog/domain/notion_import/notion_markdown.dart';
import 'package:belog/features/blog/domain/notion_import/notion_page_selection.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_file_picker.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_messages.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_report_view.dart';
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
    this.publishedWorks,
    this.onOpenArticle,
  });
  final NotionImportRepository repository;
  final NowaveSessionIdentity identity;
  final NowaveSessionFence fence;
  final AppUserCubit userCubit;
  final VoidCallback? onApplyStarted;

  /// The file picker; the system document picker when null.
  final NotionImportFilePicker? pickFiles;

  /// Whether each of the account's works it can see is published, by work
  /// ID, or null when they cannot be read. Asked once after an import so the
  /// result can say which articles can be read now and which were saved as
  /// drafts; a work it does not list is left unsaid.
  final Future<Map<String, bool>?> Function()? publishedWorks;

  /// Opens the published article [slug]; the host closes the sheet first.
  final ValueChanged<String>? onOpenArticle;

  @override
  State<NotionImportSheet> createState() => _NotionImportSheetState();
}

class _NotionImportSheetState extends State<NotionImportSheet> {
  final _input = TextEditingController();
  StreamSubscription<void>? _subscription;
  StreamSubscription<AppUserState>? _userSubscription;
  NotionBundle? _source;
  final Set<int> _selected = {};

  /// Which pages travel together and which images each uses.
  NotionPageSelection _selection = NotionPageSelection.empty;

  /// What converting Markdown could not carry, shown before the preview.
  List<NotionMarkdownWarning> _warnings = const [];

  /// The chosen file names and how many pages they made, when the source is
  /// files rather than pasted text.
  String? _filesRead;

  /// The export's images the pages use.
  Map<String, NotionLocalImage> _images = const {};

  /// Which works of [_published]'s report are published, once known.
  (NotionImportReport, Map<String, bool>)? _published;

  /// Uploads the export's images for this sheet's account.
  late final _uploader = NotionImageUploader(
    repository: widget.repository,
    fence: widget.fence,
  );

  /// Upload progress while images are uploaded before a preview.
  (int, int)? _uploading;

  /// Images the media service refused, left out of the last preview.
  List<String> _skippedImages = const [];
  NotionBundle? _snapshot;
  NotionImportReport? _report;
  NotionImportPlan? _plan;
  Timer? _expiryTimer;

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

  @override
  void dispose() {
    _discardPlan();
    unawaited(_subscription?.cancel());
    unawaited(_userSubscription?.cancel());
    _input.dispose();
    super.dispose();
  }

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

  /// Forgets the last preview: its report, its snapshot, the pending
  /// confirmation and any message. Call inside `setState`.
  void _resetPreview({String? error}) {
    _skippedImages = const [];
    _snapshot = null;
    _report = null;
    _error = error;
    _confirming = false;
  }

  /// Forgets the source as well as its preview. Call inside `setState`.
  void _resetSource({String? error}) {
    _source = null;
    _selected.clear();
    _selection = NotionPageSelection.empty;
    _warnings = const [];
    _filesRead = null;
    _images = const {};
    _resetPreview(error: error);
  }

  void _checkIdentity() {
    if (_current || _invalidated) return;
    _invalidated = true;
    _discardPlan();
    _input.clear();
    // The uploaded addresses belong to the account that uploaded them.
    _uploader.forget();
    if (mounted) setState(_resetSource);
  }

  void _changed(String _) {
    _discardPlan();
    setState(_resetSource);
  }

  void _fail(String message) => setState(() => _resetSource(error: message));

  void _readBundle() {
    if (!_current || _busy) return;
    _discardPlan();
    try {
      _show(readPastedNotionText(_input.text));
    } on NotionImportSourceException catch (error) {
      _fail(switch (error.error) {
        NotionImportSourceError.invalidBundle ||
        NotionImportSourceError.noPages => context.l10n.notionImportInvalid,
        _ => notionSourceErrorMessage(context.l10n, error),
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
      if (mounted && _current) {
        _fail(notionSourceErrorMessage(context.l10n, error));
      }
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
      _fail(notionSourceErrorMessage(context.l10n, error));
    }
  }

  /// Every page starts selected, as on the web: importing an export is the
  /// usual intent, and the author unticks what should stay behind.
  void _show(NotionImportSource source, {String? filesRead}) {
    final selection = NotionPageSelection.of(source.bundle);
    setState(() {
      _source = source.bundle;
      _selection = selection;
      _selected
        ..clear()
        ..addAll(selection.all);
      _warnings = source.warnings;
      _filesRead = filesRead;
      _images = source.images;
      _resetPreview();
    });
  }

  void _setSelection(Set<int> selection) {
    if (!_current || _busy) return;
    _discardPlan();
    setState(() {
      _selected
        ..clear()
        ..addAll(selection);
      _resetPreview();
    });
  }

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

  /// Uploads the images [keys] name and returns their addresses; an image
  /// the media service refuses is left out and named. Null when the upload
  /// stops: a lost connection, a rate limit or a session change. What was
  /// uploaded stays known, so trying again uploads only the rest.
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
      _resetPreview();
      _uploading = (0, keys.length);
    });
    final outcome = await _uploader.upload(
      keys,
      _images,
      stillWanted: () => mounted && _current,
      onProgress: (done, total) {
        if (mounted) setState(() => _uploading = (done, total));
      },
    );
    if (outcome is NotionImageUploadAbandoned || !mounted) return null;
    setState(() {
      _busy = false;
      _uploading = null;
      switch (outcome) {
        case NotionImagesUploaded(:final skipped):
          _error = null;
          _skippedImages = skipped;
        case NotionImageUploadStopped(:final failure):
          _error = failure.code == 'server.RATE_LIMITED'
              ? notionRateLimitedMessage(l10n, failure)
              : l10n.notionImportImageUploadFailed(
                  localizedFailure(l10n, failure),
                );
          _skippedImages = const [];
        case NotionImageUploadAbandoned():
          break;
      }
    });
    return outcome is NotionImagesUploaded ? outcome.urls : null;
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
    if (apply) {
      // The plan is spent by this request whatever its answer.
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _plan = null;
    } else {
      _discardPlan();
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
    final l10n = context.l10n;
    setState(() {
      _busy = false;
      result.fold(
        (failure) {
          _report = null;
          _snapshot = null;
          // A timeout, invalid response or connection loss cannot prove that a
          // server-side apply did not land; require a fresh preview.
          _error = failure.code == 'notion.planInvalid'
              ? l10n.notionImportPlanInvalid
              : failure.code == 'server.RATE_LIMITED'
              ? notionRateLimitedMessage(l10n, failure)
              : apply
              ? l10n.notionImportOutcomeUnknown
              : localizedFailure(l10n, failure);
        },
        (report) {
          final next = report.plan;
          final consistent =
              report.applied == apply &&
              (apply ||
                  (next != null &&
                      next.usable(bundle: bundle, fence: widget.fence)));
          if (!consistent) {
            next?.discard();
            _report = null;
            _snapshot = null;
            _error = apply
                ? l10n.notionImportOutcomeUnknown
                : l10n.notionImportInvalidReport;
          } else {
            _report = report;
            _snapshot = apply ? null : bundle;
            if (next != null && !apply) _watchPlan(next);
            if (apply) unawaited(_loadPublished(report));
          }
        },
      );
    });
  }

  /// After an import, which of its works can be read now.
  Future<void> _loadPublished(NotionImportReport report) async {
    final load = widget.publishedWorks;
    if (load == null || !report.pages.any((page) => _openable(page) != null)) {
      return;
    }
    final Map<String, bool>? works;
    try {
      works = await load();
    } catch (_) {
      return;
    }
    if (works == null || !mounted || !_current || !identical(_report, report)) {
      return;
    }
    final known = works;
    setState(() => _published = (report, known));
  }

  /// The work an applied page landed in, when there is one to open.
  static String? _openable(NotionImportPage page) => switch (page.action) {
    NotionImportAction.create ||
    NotionImportAction.update ||
    NotionImportAction.skip when page.slug.isNotEmpty => page.articleId,
    _ => null,
  };

  /// Where an imported page can be found: open it when it is published,
  /// otherwise say it waits in My articles as a draft.
  List<Widget> _landed(NotionImportReport report, NotionImportPage page) {
    final work = _openable(page);
    final published = _published;
    if (work == null || published == null || !identical(published.$1, report)) {
      return const [];
    }
    final isPublished = published.$2[work];
    if (isPublished == null) return const [];
    final l10n = context.l10n;
    final open = widget.onOpenArticle;
    if (!isPublished) {
      return [
        Text(
          l10n.notionImportLandedDraft,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    if (open == null) return const [];
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _busy ? null : () => open(page.slug),
          icon: const Icon(Icons.open_in_new, size: NoWaveIconSize.inline),
          label: Text(l10n.notionImportOpenArticle),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                            ..._sourceInputs(l10n),
                            ..._sourceSummary(),
                            ..._progressAndMessages(l10n),
                            ..._reportSection(l10n),
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

  /// Where the source comes from: chosen files or pasted text.
  List<Widget> _sourceInputs(AppLocalizations l10n) => [
    Text(l10n.notionImportDescription),
    const SizedBox(height: NoWaveSpacing.small),
    Text(
      l10n.notionImportExportHint,
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: NoWaveSpacing.medium),
    OutlinedButton.icon(
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
      decoration: InputDecoration(labelText: l10n.notionImportInput),
    ),
    const SizedBox(height: NoWaveSpacing.medium),
    OutlinedButton(
      onPressed: _busy ? null : _readBundle,
      child: Text(l10n.notionImportReadBundle),
    ),
  ];

  /// What was read, what conversion lost, and the pages to choose from.
  List<Widget> _sourceSummary() {
    final source = _source;
    if (source == null) return const [];
    final filesRead = _filesRead;
    return [
      if (filesRead != null) ...[
        const SizedBox(height: NoWaveSpacing.medium),
        Text(filesRead, key: const ValueKey('notion-import-files')),
      ],
      if (_warnings.isNotEmpty) ...[
        const SizedBox(height: NoWaveSpacing.medium),
        NotionConversionWarnings(warnings: _warnings),
      ],
      const SizedBox(height: NoWaveSpacing.medium),
      NotionImportPageList(
        source: source,
        selection: _selection,
        selected: _selected,
        enabled: !_busy,
        onChanged: _setSelection,
        onPreview: _preview,
      ),
    ];
  }

  List<Widget> _progressAndMessages(AppLocalizations l10n) {
    final error = _error;
    return [
      if (_busy) ...[
        const SizedBox(height: NoWaveSpacing.small),
        NoWaveLoadingLabel(
          label: switch (_uploading) {
            (final done, final total) => l10n.notionImportUploadingImages(
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
      if (error != null) ...[
        const SizedBox(height: NoWaveSpacing.medium),
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  /// The plan or result, and - for a plan that can still be applied - the
  /// two-step confirmation.
  List<Widget> _reportSection(AppLocalizations l10n) {
    final report = _report;
    if (report == null) return const [];
    final snapshot = _snapshot;
    return [
      const SizedBox(height: NoWaveSpacing.large),
      NotionImportReportView(
        report: report,
        landed: (page) => _landed(report, page),
      ),
      if (report.canApply && snapshot != null && _plan != null) ...[
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
            onPressed: _busy ? null : () => setState(() => _confirming = true),
            child: Text(l10n.notionImportReviewConfirm),
          )
        else ...[
          Text(l10n.notionImportConfirmPrompt),
          FilledButton(
            onPressed: _busy ? null : () => _submit(snapshot, apply: true),
            child: Text(l10n.notionImportConfirm),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _confirming = false),
            child: Text(l10n.actionCancel),
          ),
        ],
      ],
    ];
  }
}
