/// A device speech voice. The platform chooses a default when no match exists.
class SpeechVoice {
  const SpeechVoice({required this.id, required this.language});
  final String id;
  final String language;
}

SpeechVoice? matchingSpeechVoice(List<SpeechVoice> voices, String language) {
  final requested = language.toLowerCase().replaceAll('_', '-');
  for (final voice in voices) {
    if (voice.language.toLowerCase().replaceAll('_', '-') == requested) {
      return voice;
    }
  }
  final family = requested.split('-').first;
  for (final voice in voices) {
    if (voice.language.toLowerCase().replaceAll('_', '-').split('-').first ==
        family) {
      return voice;
    }
  }
  return null;
}

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

/// Only the follow preference is persisted; article text and audio are not.
abstract interface class ReadAloudPreferences {
  Future<bool> loadFollow();
  Future<void> saveFollow(bool enabled);
}
