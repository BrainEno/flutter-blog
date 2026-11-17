import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:belog/features/blog/presentation/editor/editor_session_config.dart';
import 'package:belog/features/blog/presentation/editor/editor_session_coordinator.dart';
import 'package:flutter/material.dart';

/// Creates or edits an article.
///
/// The page is pushed as `/editor` (new article) or `/profile/editor` with
/// the article passed as `extra`. It pops with `true` when something was
/// published, updated or deleted, so the page below can refresh its list.
///
/// A [queueEntry] resumes the text and cover of a *failed* publish that never
/// reached the server. A failed *edit* also resumes in update mode: it names
/// the article it targets, so the text is written back to that article rather
/// than published as a second one. Either way the old entry is deleted once
/// this one has a successor - sent, or queued again.
class BlogEditorPage extends StatelessWidget {
  final Blog? blog;
  final PublishQueueEntry? queueEntry;
  final BlogDraftStore? draftStore;
  final NowaveSessionIdentity? sessionIdentity;
  final PublishQueueStore? publishQueueStore;
  final PublishQueueDrainer? publishQueueDrainer;

  /// The category catalog read. Injectable so a test can answer without a
  /// server; production resolves the shared, credential-free use case.
  final GetCategories? getCategories;

  /// Fresh article read used only for an explicit conditional-write conflict
  /// review. The user must opt in before its revision can rebase a draft.
  final GetBlogById? getBlogById;

  /// The private media-library read. Injectable so picker tests can stay local.
  final GetUserMediaLibraryPage? getUserMediaLibraryPage;
  final NotionImportRepository? notionImportRepository;
  final NotionExportRepository? notionExportRepository;
  const BlogEditorPage({
    super.key,
    this.blog,
    this.queueEntry,
    this.draftStore,
    this.sessionIdentity,
    this.publishQueueStore,
    this.publishQueueDrainer,
    this.getCategories,
    this.getBlogById,
    this.getUserMediaLibraryPage,
    this.notionImportRepository,
    this.notionExportRepository,
  });

  @override
  Widget build(BuildContext context) => EditorSessionCoordinator(
    config: EditorSessionConfig(
      blog: blog,
      queueEntry: queueEntry,
      draftStore: draftStore,
      sessionIdentity: sessionIdentity,
      publishQueueStore: publishQueueStore,
      publishQueueDrainer: publishQueueDrainer,
      getCategories: getCategories,
      getBlogById: getBlogById,
      getUserMediaLibraryPage: getUserMediaLibraryPage,
      notionImportRepository: notionImportRepository,
      notionExportRepository: notionExportRepository,
    ),
  );
}
