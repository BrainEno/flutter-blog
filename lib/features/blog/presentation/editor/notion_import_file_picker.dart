import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import_source.dart';
import 'package:file_selector/file_selector.dart';

/// Asks the author for files; null or empty when they cancel.
typedef NotionImportFilePicker = Future<List<NotionImportFile>?> Function();

/// The system document picker, any type: Notion's ZIP and Markdown files
/// carry inconsistent MIME types across devices, so the picker does not
/// filter and [readNotionImportFiles] decides by name. Sizes are checked
/// before any file is read into memory.
Future<List<NotionImportFile>?> pickNotionImportFiles() async {
  final files = await openFiles();
  if (files.isEmpty) return null;
  var total = 0;
  for (final file in files) {
    total += await file.length();
    if (total > AppLimits.notionImportMaxSourceBytes) {
      throw const NotionImportSourceException(NotionImportSourceError.tooLarge);
    }
  }
  return [
    for (final file in files)
      NotionImportFile(name: file.name, bytes: await file.readAsBytes()),
  ];
}
