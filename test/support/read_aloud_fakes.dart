import 'dart:async';

import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';

class FakeSpeechCall {
  const FakeSpeechCall(
    this.id,
    this.text,
    this.language,
    this.voice,
    this.rate,
  );
  final String id;
  final String text;
  final String language;
  final SpeechVoice? voice;
  final double rate;
}

class FakeSpeechEngine implements SpeechEngine {
  final eventController = StreamController<SpeechEvent>.broadcast(sync: true);
  final calls = <FakeSpeechCall>[];
  final voices = <SpeechVoice>[
    const SpeechVoice(id: 'english', language: 'en-US'),
    const SpeechVoice(id: 'chinese', language: 'zh-CN'),
  ];
  int initializationCount = 0;
  int stopCount = 0;
  bool unsupported = false;
  bool failSpeak = false;
  Completer<void>? stopGate;

  @override
  Stream<SpeechEvent> get events => eventController.stream;

  @override
  Future<List<SpeechVoice>> initialize() async {
    initializationCount++;
    if (unsupported) throw UnsupportedError('no speech engine');
    return voices;
  }

  @override
  Future<void> speak({
    required String utteranceId,
    required String text,
    required String language,
    required SpeechVoice? voice,
    required double rate,
  }) async {
    if (failSpeak) throw StateError('speech failure');
    calls.add(FakeSpeechCall(utteranceId, text, language, voice, rate));
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final gate = stopGate;
    if (gate != null) await gate.future;
  }

  void event(String id, SpeechEventType type, {int start = 0, int end = 0}) {
    eventController.add(
      SpeechEvent(utteranceId: id, type: type, start: start, end: end),
    );
  }

  Future<void> close() => eventController.close();
}

class FakeReadAloudPreferences implements ReadAloudPreferences {
  bool follow = true;
  bool failLoad = false;
  bool failSave = false;
  Completer<bool>? loadGate;
  final writes = <bool>[];

  @override
  Future<bool> loadFollow() async {
    if (failLoad) throw StateError('storage unavailable');
    final gate = loadGate;
    return gate == null ? follow : await gate.future;
  }

  @override
  Future<void> saveFollow(bool enabled) async {
    if (failSave) throw StateError('storage unavailable');
    writes.add(enabled);
    follow = enabled;
  }
}

Future<void> flushSpeech() => Future<void>.delayed(Duration.zero);
