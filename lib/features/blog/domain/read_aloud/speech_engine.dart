/// A device speech voice. [id] is an opaque platform identifier; [displayName]
/// is supplied only to help a person distinguish installed voices in the reader
/// controls. The platform chooses its default when no compatible voice exists.
class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.language,
    String? displayName,
  }) : displayName = displayName ?? id;

  final String id;
  final String language;
  final String displayName;
}

/// Compare a voice to a requested language without requiring a package for a
/// full BCP-47 parser. Engines commonly return either `en-US` or `en_US`; an
/// exact match wins and a language-family voice remains a supported fallback.
bool voiceSupportsLanguage(SpeechVoice voice, String language) {
  final requested = _normalizedSpeechLanguage(language);
  final candidate = _normalizedSpeechLanguage(voice.language);
  if (requested.isEmpty || candidate.isEmpty) return false;
  return requested == candidate ||
      requested.split('-').first == candidate.split('-').first;
}

SpeechVoice? matchingSpeechVoice(List<SpeechVoice> voices, String language) {
  final requested = _normalizedSpeechLanguage(language);
  if (requested.isEmpty) return null;
  for (final voice in voices) {
    if (_normalizedSpeechLanguage(voice.language) == requested) return voice;
  }
  for (final voice in voices) {
    if (voiceSupportsLanguage(voice, requested)) return voice;
  }
  return null;
}

String _normalizedSpeechLanguage(String value) =>
    value.toLowerCase().trim().replaceAll('_', '-');

enum SpeechEventType { started, range, completed, cancelled, error }

/// Events carry the platform utterance ID, so callbacks from a stopped or
/// replaced article cannot advance a newer playback.
class SpeechEvent {
  const SpeechEvent({
    required this.utteranceId,
    required this.type,
    this.start = 0,
    this.end = 0,
  });
  final String utteranceId;
  final SpeechEventType type;
  final int start;
  final int end;
}

abstract interface class SpeechEngine {
  /// Empty when a platform cannot enumerate voices; a default may still work.
  Future<List<SpeechVoice>> initialize();
  Stream<SpeechEvent> get events;

  /// Completes when the platform accepts the utterance, not when it finishes.
  Future<void> speak({
    required String utteranceId,
    required String text,
    required String language,
    required SpeechVoice? voice,
    required double rate,
  });

  Future<void> stop();
}
