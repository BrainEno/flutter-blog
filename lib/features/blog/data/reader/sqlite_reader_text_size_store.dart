import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';

/// The reader's text size in the metadata table, next to the read-aloud
/// preferences. Device-wide and never synced; signing out keeps it, like the
/// theme.
class SqliteReaderTextSizeStore implements ReaderTextSizeStore {
  SqliteReaderTextSizeStore(this.database);

  static const _key = 'reader_text_size_v1';
  final AppDatabase database;

  @override
  Future<ReaderTextSize> load() async =>
      ReaderTextSize.parse(await database.readMetadata(_key));

  @override
  Future<void> save(ReaderTextSize size) =>
      database.writeMetadata(_key, size.name);
}
