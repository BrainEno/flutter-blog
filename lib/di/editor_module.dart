import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/sqlite_draft_store.dart';
import 'package:belog/features/blog/data/notion_export/notion_export_repository_impl.dart';
import 'package:belog/features/blog/data/notion_import/notion_import_repository_impl.dart';
import 'package:belog/features/blog/domain/notion_export/notion_export.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';
import 'package:belog/features/blog/domain/repositories/blog_draft_store.dart';
import 'package:get_it/get_it.dart';

/// What the editor keeps beside the article itself: local drafts and the
/// user-initiated Notion bundle import/export (through the no-wave backend;
/// no Notion token in the app).
void registerEditorModule(GetIt locator, DependencyContext context) {
  final database = context.database;
  final apiBaseUrl = context.apiBaseUrl;
  final apiClient = context.apiClient;
  locator
    ..registerLazySingleton<NotionExportRepository>(
      () => NotionExportRepositoryImpl(apiClient),
    )
    ..registerLazySingleton<NotionImportRepository>(
      () => NotionImportRepositoryImpl(apiClient),
    )
    ..registerLazySingleton<BlogDraftStore>(
      () => SqliteBlogDraftStore(database, apiBaseUrl: apiBaseUrl),
    );
}
