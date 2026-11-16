import 'dart:convert';

import 'package:belog/core/storage/app_database.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';

/// Device-local reader preferences in the existing metadata table.
///
/// Each field has its own key so changing speed on one retained article page
/// cannot accidentally overwrite a voice choice made on another. Writes run in
/// order even after a failed database operation; the article viewer treats a
/// persistence failure as non-fatal and continues with its in-memory setting.
class SqliteReadAloudPreferences implements ReadAloudPreferences {
  SqliteReadAloudPreferences(this.database);

  static const _followKey = 'read_aloud_follow_v1';
  static const _speedKey = 'read_aloud_speed_v1';
  static const _voicesKey = 'read_aloud_voices_v1';
  final AppDatabase database;
  Future<void> _tail = Future<void>.value();

  @override
  Future<ReadAloudSettings> load() async {
    await _tail;
    final values = await Future.wait<String?>([
      database.readMetadata(_followKey),
      database.readMetadata(_speedKey),
      database.readMetadata(_voicesKey),
    ]);
    final follow = values[0] != '0';
    final speed = _readSpeed(values[1]);
    return ReadAloudSettings(
      follow: follow,
      speed: speed,
      preferredVoiceIds: _readVoiceIds(values[2]),
    );
  }

  @override
  Future<void> saveFollow(bool enabled) =>
      _enqueue(() => database.writeMetadata(_followKey, enabled ? '1' : '0'));

  @override
  Future<void> saveSpeed(double speed) {
    final safe = sanitizeSpeechRate(speed);
    return _enqueue(() => database.writeMetadata(_speedKey, '$safe'));
  }

  @override
  Future<void> savePreferredVoice(String language, String? voiceId) {
    final normalizedLanguage = normalizeSpeechLanguage(language);
    if (normalizedLanguage.isEmpty) return Future<void>.value();
    final normalizedVoiceId = sanitizeSpeechVoiceId(voiceId);
    return _enqueue(() async {
      final values = _readVoiceIds(await database.readMetadata(_voicesKey));
      if (normalizedVoiceId == null) {
        values.remove(normalizedLanguage);
      } else {
        values[normalizedLanguage] = normalizedVoiceId;
      }
      await database.writeMetadata(_voicesKey, _encodeVoiceIds(values));
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    // Keep later user choices alive when storage filled up or a previous write
    // failed. The failing caller still receives its original failure.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  double _readSpeed(String? raw) {
    final value = double.tryParse(raw ?? '');
    return value == null ? defaultSpeechRate : sanitizeSpeechRate(value);
  }

  Map<String, String> _readVoiceIds(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 8192) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final values = <String, String>{};
      for (final entry in decoded.entries) {
        if (values.length >= 16) break;
        if (entry.key is! String || entry.value is! String) continue;
        final language = normalizeSpeechLanguage(entry.key as String);
        final id = sanitizeSpeechVoiceId(entry.value as String);
        if (language.isNotEmpty && id != null) values[language] = id;
      }
      return values;
    } catch (_) {
      // Metadata survives app upgrades and could have been written by a broken
      // older build. A malformed optional preference must not hide the player.
      return <String, String>{};
    }
  }

  String _encodeVoiceIds(Map<String, String> values) {
    final entries = values.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode(<String, String>{
      for (final entry in entries) entry.key: entry.value,
    });
  }
}
