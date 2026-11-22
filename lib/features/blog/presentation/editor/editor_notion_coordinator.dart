import 'dart:async';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/presentation/editor/notion_export_sheet.dart';
import 'package:belog/features/blog/presentation/editor/notion_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:belog/router/route_paths.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// Owns the one active Notion sheet and its exact route. The host provides a
/// session-current predicate; an invalidated editor must dismiss the route and
/// can never start another operation under the replacement account.
class EditorNotionCoordinator {
  EditorNotionCoordinator({
    required this.identity,
    required this.userCubit,
    required this.userId,
    required this.generation,
    required bool Function() isCurrent,
    required NotionImportRepository? Function() importRepository,
    required NotionExportRepository? Function() exportRepository,
    Future<Map<String, bool>?> Function()? publishedWorks,
    void Function(BuildContext context, String slug)? openArticle,
  }) : _isCurrent = isCurrent,
       _importRepository = importRepository,
       _exportRepository = exportRepository,
       _publishedWorks = publishedWorks,
       _openArticle = openArticle ?? _openInReader;

  final NowaveSessionIdentity identity;
  final AppUserCubit userCubit;
  final String? userId;
  final int generation;
  final bool Function() _isCurrent;
  final NotionImportRepository? Function() _importRepository;
  final NotionExportRepository? Function() _exportRepository;
  final Future<Map<String, bool>?> Function()? _publishedWorks;
  final void Function(BuildContext context, String slug) _openArticle;
  NavigatorState? _navigator;
  Route<dynamic>? _route;
  bool _open = false;
  bool _applyStarted = false;

  /// True after an import may have changed the original account on the server.
  bool get applyStarted => _applyStarted;

  Future<void> openImport(BuildContext context) async {
    if (!_isCurrent() || _open) return;
    final repository =
        _importRepository() ??
        (GetIt.instance.isRegistered<NotionImportRepository>()
            ? GetIt.instance<NotionImportRepository>()
            : null);
    if (repository == null) {
      showSnackBar(context, context.l10n.notionImportUnavailable);
      return;
    }
    _navigator = Navigator.of(context, rootNavigator: true);
    _open = true;
    String? article;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) {
          _route = ModalRoute.of(sheetContext);
          return NotionImportSheet(
            repository: repository,
            identity: identity,
            userCubit: userCubit,
            onApplyStarted: () => _applyStarted = true,
            fence: NowaveSessionFence(userId: userId!, generation: generation),
            publishedWorks: _publishedWorks ?? _ownPublishedWorks,
            onOpenArticle: (slug) {
              article = slug;
              Navigator.of(sheetContext).pop();
            },
          );
        },
      );
    } finally {
      _open = false;
      _navigator = null;
      _route = null;
    }
    // The reader opens above the editor, whose draft stays as it was; back
    // returns to it.
    final slug = article;
    if (slug != null && context.mounted && _isCurrent()) {
      _openArticle(context, slug);
    }
  }

  /// The account's own works and whether each is published, read across
  /// languages - one status per work. Null when it cannot be read.
  Future<Map<String, bool>?> _ownPublishedWorks() async {
    final owner = userId;
    if (owner == null || !GetIt.instance.isRegistered<BlogRepository>()) {
      return null;
    }
    final result = await GetIt.instance<BlogRepository>().getMyArticleEditions(
      userId: owner,
    );
    return result.fold((_) => null, (editions) {
      final works = <String, bool>{};
      for (final blog in editions.blogs) {
        final work = blog.authoringArticleId;
        if (work != null) works[work] = !blog.isDraft;
      }
      return works;
    });
  }

  static void _openInReader(BuildContext context, String slug) {
    unawaited(
      context.push(
        shellBranchLocation(
          GoRouterState.of(context).uri,
          RoutePaths.view(slug),
        ),
      ),
    );
  }

  Future<void> openExport(BuildContext context, String? slug) async {
    if (!_isCurrent() || _open || slug == null || slug.isEmpty) {
      return;
    }
    final repository =
        _exportRepository() ??
        (GetIt.instance.isRegistered<NotionExportRepository>()
            ? GetIt.instance<NotionExportRepository>()
            : null);
    if (repository == null) {
      showSnackBar(context, context.l10n.notionExportUnavailable);
      return;
    }
    _navigator = Navigator.of(context, rootNavigator: true);
    _open = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) {
          _route = ModalRoute.of(sheetContext);
          return NotionExportSheet(
            repository: repository,
            identity: identity,
            userCubit: userCubit,
            slug: slug,
            fence: NowaveSessionFence(userId: userId!, generation: generation),
          );
        },
      );
    } finally {
      _open = false;
      _navigator = null;
      _route = null;
    }
  }

  void dismiss() {
    if (!_open) return;
    final navigator = _navigator;
    final route = _route;
    _open = false;
    _navigator = null;
    if (navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeRoute = route ?? _route;
      if (navigator.mounted && activeRoute != null && activeRoute.isActive) {
        navigator.removeRoute(activeRoute);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
