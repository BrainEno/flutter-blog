import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';

/// One non-sensitive device preference in the existing metadata table.
class SqliteReadAloudPreferences implements ReadAloudPreferences {
  SqliteReadAloudPreferences(this.database);
  static const _key = 'read_aloud_follow_v1';
  final AppDatabase database;
  Future<void> _tail = Future<void>.value();

  @override
  Future<bool> loadFollow() async {
    await _tail;
    return await database.readMetadata(_key) != '0';
  }

  @override
  Future<void> saveFollow(bool enabled) {
    final result = _tail.then(
      (_) => database.writeMetadata(_key, enabled ? '1' : '0'),
    );
    // Later writes must still run after an earlier storage failure.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
