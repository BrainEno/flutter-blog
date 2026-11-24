import 'package:belog/core/common/media/cover_crop.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/entities/publish_queue_entry.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/domain/usecase/get_blog_by_id.dart';
import 'package:belog/features/blog/domain/usecase/get_categories.dart';
import 'package:belog/features/blog/domain/usecase/upload_article_image.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';

/// Route inputs and optional test dependencies for one editor session. These
/// are configuration, not a draft or permission to write. The coordinator owns
/// all mutable controllers, async work and session checks.
class EditorSessionConfig {
  const EditorSessionConfig({
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
    this.uploadArticleImage,
    this.pickCoverImage,
    this.coverCropper,
  });
  final Blog? blog;
  final PublishQueueEntry? queueEntry;
  final BlogDraftStore? draftStore;
  final NowaveSessionIdentity? sessionIdentity;
  final PublishQueueStore? publishQueueStore;
  final PublishQueueDrainer? publishQueueDrainer;
  final GetCategories? getCategories;
  final GetBlogById? getBlogById;
  final GetUserMediaLibraryPage? getUserMediaLibraryPage;
  final NotionImportRepository? notionImportRepository;
  final NotionExportRepository? notionExportRepository;

  /// Uploads pictures placed in the body; without one the toolbar offers no
  /// image button.
  final UploadArticleImage? uploadArticleImage;

  /// The gallery pick behind the cover slot; production uses [pickImage].
  final Future<PickedImage?> Function()? pickCoverImage;

  /// The codec behind the cover crop step; production decodes in an isolate.
  final CoverCropper? coverCropper;
}
