import 'dart:async';

import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:flutter/services.dart';

/// The platform bridges use utterance IDs and return UTF-16 word ranges.
/// They never send article text to the app's backend or create audio files.
class PlatformSpeechEngine implements SpeechEngine {
  PlatformSpeechEngine({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('belog/read_aloud') {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  final MethodChannel _channel;
  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast(sync: true);

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<List<SpeechVoice>> initialize() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'initialize',
    );
    if (result == null || result['available'] != true) {
      throw UnsupportedError('Device speech synthesis is unavailable.');
    }
    final voices = <SpeechVoice>[];
    final rawVoices = result['voices'];
    if (rawVoices is List) {
      for (final raw in rawVoices) {
        if (raw is! Map) continue;
        final id = raw['id'];
        final language = raw['language'];
        if (id is String && language is String && id.isNotEmpty) {
          voices.add(SpeechVoice(id: id, language: language));
        }
      }
    }
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
    final accepted = await _channel.invokeMethod<bool>('speak', {
      'id': utteranceId,
      'text': text,
      'language': language,
      'voice': voice?.id,
      'rate': rate,
    });
    if (accepted != true) throw StateError('Device speech was not accepted.');
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method != 'event' || call.arguments is! Map) return;
    final data = call.arguments as Map;
    final id = data['id'];
    final name = data['type'];
    if (id is! String || name is! String) return;
    final type = switch (name) {
      'started' => SpeechEventType.started,
      'range' => SpeechEventType.range,
      'completed' => SpeechEventType.completed,
      'cancelled' => SpeechEventType.cancelled,
      'error' => SpeechEventType.error,
      _ => null,
    };
    if (type == null) return;
    final start = data['start'];
    final end = data['end'];
    _events.add(
      SpeechEvent(
        utteranceId: id,
        type: type,
        start: start is int ? start : 0,
        end: end is int ? end : 0,
      ),
    );
  }
}
