import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a private, server-exported bundle only for the opening session.
class NotionExportSheet extends StatefulWidget {
  const NotionExportSheet({
    super.key,
    required this.repository,
    required this.identity,
    required this.userCubit,
    required this.fence,
    required this.slug,
    this.copyText,
  });
  final NotionExportRepository repository;
  final NowaveSessionIdentity identity;
  final AppUserCubit userCubit;
  final NowaveSessionFence fence;
  final String slug;

  /// Injectable platform seam for tests; called only on explicit user action.
  final Future<void> Function(String text)? copyText;

  @override
  State<NotionExportSheet> createState() => _NotionExportSheetState();
}

class _NotionExportSheetState extends State<NotionExportSheet> {
  StreamSubscription<void>? _identitySubscription;
  StreamSubscription<AppUserState>? _userSubscription;
  bool _invalidated = false;
  bool _busy = false;
  bool _copied = false;
  bool _copying = false;
  String? _error;
  NotionExportResult? _result;

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
    _identitySubscription = widget.identity.identityChanges.listen(
      (_) => _checkIdentity(),
    );
    _userSubscription = widget.userCubit.stream.listen((_) => _checkIdentity());
  }

  void _checkIdentity() {
    if (!_current && !_invalidated) {
      _invalidated = true;
      if (mounted) {
        setState(() {
          _result = null;
          _error = null;
          _copied = false;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_identitySubscription?.cancel());
    unawaited(_userSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
      _copied = false;
    });
    final response = await widget.repository.export(
      slug: widget.slug,
      sessionFence: widget.fence,
    );
    if (!mounted || !_current) return;
    setState(() {
      _busy = false;
      response.fold(
        (failure) => _error = localizedFailure(context.l10n, failure),
        (result) => _result = result,
      );
    });
  }

  Future<void> _copy() async {
    final result = _result;
    if (!_current || _busy || result == null || result.missing) return;
    setState(() {
      _busy = true;
      _copying = true;
      _error = null;
      _copied = false;
    });
    try {
      final copy =
          widget.copyText ??
          ((String text) => Clipboard.setData(ClipboardData(text: text)));
      await copy(result.bundleJson);
      if (mounted && _current) {
        setState(() {
          _busy = false;
          _copying = false;
          _copied = true;
        });
      }
    } catch (_) {
      if (mounted && _current) {
        setState(() {
          _busy = false;
          _copying = false;
          _error = context.l10n.notionExportCopyFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(NoWaveSpacing.medium),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.notionExportTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
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
                      padding: const EdgeInsets.all(NoWaveSpacing.medium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.notionExportDescription),
                          const SizedBox(height: NoWaveSpacing.medium),
                          OutlinedButton(
                            onPressed: _busy ? null : _load,
                            child: Text(l10n.notionExportLoad),
                          ),
                          if (_busy) ...[
                            const SizedBox(height: NoWaveSpacing.small),
                            NoWaveLoadingLabel(
                              label: _copying
                                  ? l10n.notionExportCopying
                                  : l10n.notionExportLoading,
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
                          if (result != null && result.missing) ...[
                            const SizedBox(height: NoWaveSpacing.medium),
                            Text(l10n.notionExportMissing),
                          ],
                          if (result != null && !result.missing) ...[
                            const SizedBox(height: NoWaveSpacing.medium),
                            Text(
                              l10n.notionExportReport,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final issue in result.issues) Text(issue),
                            for (final edition in result.editions) ...[
                              const Divider(),
                              Text(
                                l10n.notionExportEdition(
                                  edition.locale,
                                  edition.fromNotion
                                      ? l10n.notionExportNotionOrigin
                                      : l10n.notionExportSiteOrigin,
                                ),
                              ),
                              for (final issue in edition.issues) Text(issue),
                            ],
                            const SizedBox(height: NoWaveSpacing.medium),
                            Text(l10n.notionExportClipboardWarning),
                            FilledButton(
                              onPressed: _busy ? null : _copy,
                              child: Text(l10n.notionExportCopy),
                            ),
                            if (_copied) Text(l10n.notionExportCopied),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
