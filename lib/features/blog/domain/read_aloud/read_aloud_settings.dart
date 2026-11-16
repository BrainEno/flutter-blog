import 'dart:collection';

import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';

/// The rates deliberately exposed by the reader. Keeping this domain list
/// shared by persistence and presentation makes a corrupt local value fall
/// back safely instead of reaching a native speech API unchecked.
const supportedSpeechRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

const defaultSpeechRate = 1.0;

/// A non-sensitive device setting for the reader.
///
/// Voice IDs are opaque identifiers issued by the operating system. They are
/// scoped to the language the article passage requests, not to an account or
/// article. The map contains no article text, audio, backend address or user
/// identity. A missing entry means to use the platform's automatic voice.
class ReadAloudSettings {
  ReadAloudSettings({
    required this.follow,
    required double speed,
    Map<String, String> preferredVoiceIds = const {},
  }) : speed = sanitizeSpeechRate(speed),
       preferredVoiceIds = UnmodifiableMapView(
         _normalizeVoiceIds(preferredVoiceIds),
       );

  const ReadAloudSettings.defaults()
    : follow = true,
      speed = defaultSpeechRate,
      preferredVoiceIds = const <String, String>{};

  final bool follow;
  final double speed;
  final Map<String, String> preferredVoiceIds;

  /// Returns the saved voice ID for [language], if it is still a safe,
  /// canonical preference. It deliberately does not claim that the current
  /// device still has that voice installed.
  String? preferredVoiceIdFor(String language) {
    final normalized = normalizeSpeechLanguage(language);
    if (normalized.isEmpty) return null;
    return preferredVoiceIds[normalized];
  }

  ReadAloudSettings copyWith({
    bool? follow,
    double? speed,
    Map<String, String>? preferredVoiceIds,
  }) {
    return ReadAloudSettings(
      follow: follow ?? this.follow,
      speed: sanitizeSpeechRate(speed ?? this.speed),
      preferredVoiceIds: preferredVoiceIds ?? this.preferredVoiceIds,
    );
  }

  ReadAloudSettings withPreferredVoice(String language, String? voiceId) {
    final normalizedLanguage = normalizeSpeechLanguage(language);
    if (normalizedLanguage.isEmpty) return this;
    final values = Map<String, String>.of(preferredVoiceIds);
    final normalizedId = sanitizeSpeechVoiceId(voiceId);
    if (normalizedId == null) {
      values.remove(normalizedLanguage);
    } else {
      values[normalizedLanguage] = normalizedId;
    }
    return copyWith(preferredVoiceIds: values);
  }

  static Map<String, String> _normalizeVoiceIds(Map<String, String> source) {
    // Limit corrupted metadata before it enters long-lived controller state.
    // The UI only permits one selection for each spoken language, so 16 is
    // intentionally far more than a normal installation can produce.
    final values = <String, String>{};
    for (final entry in source.entries) {
      if (values.length >= 16) break;
      final language = normalizeSpeechLanguage(entry.key);
      final id = sanitizeSpeechVoiceId(entry.value);
      if (language.isEmpty || id == null) continue;
      values[language] = id;
    }
    return values;
  }
}

/// A language tag suitable for matching operating-system voices and metadata
/// keys. It intentionally accepts the common underscore form returned by a
/// few speech engines, while not attempting to validate all BCP-47 subtags.
String normalizeSpeechLanguage(String value) {
  final pieces = value
      .trim()
      .replaceAll('_', '-')
      .split('-')
      .where((piece) => piece.isNotEmpty)
      .toList(growable: false);
  if (pieces.isEmpty || pieces.first.length < 2 || pieces.first.length > 8) {
    return '';
  }
  if (!RegExp(r'^[A-Za-z]+$').hasMatch(pieces.first)) return '';
  final result = <String>[pieces.first.toLowerCase()];
  for (final piece in pieces.skip(1)) {
    if (piece.length > 8 || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(piece)) {
      return '';
    }
    if (piece.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(piece)) {
      result.add(piece.toUpperCase());
    } else if (piece.length == 4 && RegExp(r'^[A-Za-z]{4}$').hasMatch(piece)) {
      result.add(
        '${piece[0].toUpperCase()}${piece.substring(1).toLowerCase()}',
      );
    } else {
      result.add(piece.toUpperCase());
    }
  }
  return result.join('-');
}

String speechLanguageFamily(String language) {
  final normalized = normalizeSpeechLanguage(language);
  return normalized.isEmpty ? '' : normalized.split('-').first;
}

/// Metadata is private app data, but native IDs can still be malformed or
/// unexpectedly huge. Refuse control characters and cap their footprint.
String? sanitizeSpeechVoiceId(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 512) return null;
  for (final unit in trimmed.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return null;
  }
  return trimmed;
}

/// Converts only supported persisted rates to a native-safe value.
double sanitizeSpeechRate(double value) =>
    supportedSpeechRates.contains(value) ? value : defaultSpeechRate;

/// Build stable, useful groups for a reader voice chooser.
///
/// Only languages that occur in the currently displayed article are included.
/// Exact voice-language matches are listed before family fallbacks, then names
/// and IDs make the order deterministic across page rebuilds. Duplicate native
/// IDs are ignored: selecting a voice remains unambiguous even if an engine
/// reports it more than once.
Map<String, List<SpeechVoice>> speechVoiceChoicesForLanguages(
  Iterable<String> languages,
  Iterable<SpeechVoice> voices,
) {
  final requested = <String>[];
  for (final value in languages) {
    final language = normalizeSpeechLanguage(value);
    if (language.isNotEmpty && !requested.contains(language)) {
      requested.add(language);
    }
  }
  final result = <String, List<SpeechVoice>>{};
  for (final language in requested) {
    final candidates = <SpeechVoice>[];
    final ids = <String>{};
    for (final voice in voices) {
      if (!voiceSupportsLanguage(voice, language) || !ids.add(voice.id)) {
        continue;
      }
      candidates.add(voice);
    }
    candidates.sort((left, right) {
      final leftExact = normalizeSpeechLanguage(left.language) == language;
      final rightExact = normalizeSpeechLanguage(right.language) == language;
      if (leftExact != rightExact) return leftExact ? -1 : 1;
      final label = left.displayName.compareTo(right.displayName);
      return label != 0 ? label : left.id.compareTo(right.id);
    });
    if (candidates.isNotEmpty) {
      result[language] = List<SpeechVoice>.unmodifiable(candidates);
    }
  }
  return Map<String, List<SpeechVoice>>.unmodifiable(result);
}

/// Prefer a still-installed explicitly selected voice. A stale or mismatched
/// saved ID is never sent to the platform; normal automatic matching remains
/// available after an OS voice was removed or renamed.
SpeechVoice? resolveSpeechVoice({
  required Iterable<SpeechVoice> voices,
  required String language,
  required ReadAloudSettings settings,
}) {
  final normalizedLanguage = normalizeSpeechLanguage(language);
  if (normalizedLanguage.isEmpty) return null;
  final preferredId = settings.preferredVoiceIdFor(normalizedLanguage);
  if (preferredId != null) {
    for (final voice in voices) {
      if (voice.id == preferredId &&
          voiceSupportsLanguage(voice, normalizedLanguage)) {
        return voice;
      }
    }
  }
  return matchingSpeechVoice(
    voices.toList(growable: false),
    normalizedLanguage,
  );
}

/// The small local persistence port for reader settings. Implementations must
/// keep values on the device; no article text, playback position or audio is
/// ever supplied to this interface.
abstract interface class ReadAloudPreferences {
  Future<ReadAloudSettings> load();
  Future<void> saveFollow(bool enabled);
  Future<void> saveSpeed(double speed);

  /// Passing null returns the language to platform-selected automatic speech.
  Future<void> savePreferredVoice(String language, String? voiceId);
}
