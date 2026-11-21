import 'dart:async';

import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_sleep_timer.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:flutter/foundation.dart';

enum ReadAloudPhase { idle, playing, paused }

enum ReadAloudNotice { hint, stopped, finished, sleepTimerFinished, error }

/// A word range, or the whole block when the voice supplies no boundaries.
class ReadAloudHighlight {
  const ReadAloudHighlight(this.start, this.end, {this.wholeBlock = false});
  final int start;
  final int end;
  final bool wholeBlock;
}

/// Page-scoped playback state. All positions are UTF-16, as in Android,
/// AVSpeechSynthesizer and Windows SAPI; chunking never splits a surrogate.
class ReadAloudController extends ChangeNotifier implements SpeechOwner {
  ReadAloudController({
    required this.document,
    required this.coordinator,
    required this.preferences,
    required this.fallbackLanguage,
    this.onFollowScroll,
    ReadAloudTimerScheduler? sleepTimerScheduler,
    DateTime Function()? now,
  }) : highlights = List.generate(
         document.blocks.length,
         (_) => ValueNotifier<ReadAloudHighlight?>(null),
       ),
       _sleepTimer = ReadAloudSleepTimer(
         scheduler: sleepTimerScheduler,
         now: now,
       ) {
    _subscription = coordinator.engine.events.listen(_onSpeechEvent);
  }

  static const speeds = supportedSpeechRates;
  final ReadAloudDocument document;
  final SpeechCoordinator coordinator;
  final ReadAloudPreferences preferences;
  final String fallbackLanguage;
  final void Function(int blockIndex, int spokenOffset)? onFollowScroll;
  final List<ValueNotifier<ReadAloudHighlight?>> highlights;
  final ReadAloudSleepTimer _sleepTimer;
  late final StreamSubscription<SpeechEvent> _subscription;

  ReadAloudPhase phase = ReadAloudPhase.idle;
  ReadAloudNotice notice = ReadAloudNotice.hint;
  bool available = false;
  ReadAloudSettings _settings = const ReadAloudSettings.defaults();
  double _progress = 0;
  double? _preview;
  List<SpeechVoice> _voices = const [];
  int _activeIndex = 0;
  int _offset = 0;
  int _run = 0;
  int _settingsVersion = 0;
  int? _markedBlock;
  int? _wordEnd;
  String? _utteranceId;
  bool _disposed = false;

  bool get follow => _settings.follow;
  double get speed => _settings.speed;
  double get progress => _preview ?? _progress;
  int get percent => (progress * 100).round();
  ReadAloudSleepTimerOption get sleepTimerOption => _sleepTimer.option;
  Duration? get sleepTimerRemaining => _sleepTimer.remaining;
  bool get hasSleepTimer => _sleepTimer.isActive;
  List<SpeechVoice> get voices => List<SpeechVoice>.unmodifiable(_voices);

  /// Only currently spoken language families appear in the picker. A single
  /// article can contain Chinese and English chunks and therefore show both.
  Map<String, List<SpeechVoice>> get voiceChoices =>
      speechVoiceChoicesForLanguages(_spokenLanguages(), _voices);

  String? preferredVoiceIdFor(String language) =>
      _settings.preferredVoiceIdFor(language);

  SpeechVoice? resolvedVoiceFor(String language) => resolveSpeechVoice(
    voices: _voices,
    language: language,
    settings: _settings,
  );

  Future<void> initialize() async {
    if (!document.hasBody || document.chunks.isEmpty) return;
    final settingsVersion = _settingsVersion;
    try {
      final value = await preferences.load();
      if (!_disposed && settingsVersion == _settingsVersion) {
        _settings = value.copyWith();
      }
    } catch (_) {
      // The default remains enabled; persistence is only a convenience.
    }
    if (_disposed) return;
    try {
      _voices = await coordinator.initialize();
      if (_disposed) return;
      available = true;
      notifyListeners();
    } catch (_) {
      // Unsupported platforms hide the entry, just like the web reference.
      if (_disposed) return;
      available = false;
      notifyListeners();
    }
  }

  void togglePlayback() {
    if (!available || _disposed) return;
    switch (phase) {
      case ReadAloudPhase.idle:
        coordinator.claim(this);
        phase = ReadAloudPhase.playing;
        notice = ReadAloudNotice.hint;
        _activeIndex = 0;
        _offset = 0;
        _progress = 0;
        _preview = null;
        _speakCurrent(scroll: true);
        return;
      case ReadAloudPhase.playing:
        phase = ReadAloudPhase.paused;
        _utteranceId = null;
        final run = ++_run;
        notifyListeners();
        _performStop(run, ReadAloudPhase.paused);
        return;
      case ReadAloudPhase.paused:
        phase = ReadAloudPhase.playing;
        _speakCurrent();
        return;
    }
  }

  void stop({bool announce = true}) {
    _stop(
      announce ? ReadAloudNotice.stopped : ReadAloudNotice.hint,
      clearSleepTimer: true,
    );
  }

  void _stop(ReadAloudNotice terminalNotice, {required bool clearSleepTimer}) {
    if (_disposed) return;
    _run++;
    _utteranceId = null;
    phase = ReadAloudPhase.idle;
    notice = terminalNotice;
    _activeIndex = 0;
    _offset = 0;
    _progress = 0;
    _preview = null;
    if (clearSleepTimer) _sleepTimer.clear();
    _clearHighlight();
    notifyListeners();
    _release();
  }

  void setSpeed(double value) {
    final safe = sanitizeSpeechRate(value);
    if (speed == safe || _disposed) return;
    _settingsVersion++;
    _settings = _settings.copyWith(speed: safe);
    notifyListeners();
    _persist(
      preferences.saveSpeed(safe),
      'saving the reading speed preference failed',
    );
    // A new utterance makes the change audible immediately. Paused playback
    // stays silent and uses the new speed when resumed.
    if (phase == ReadAloudPhase.playing) _speakCurrent();
  }

  void setFollow(bool value) {
    if (follow == value || _disposed) return;
    _settingsVersion++;
    _settings = _settings.copyWith(follow: value);
    if (!follow) {
      _clearHighlight();
    } else if (phase != ReadAloudPhase.idle) {
      final wordEnd = _wordEnd;
      if (wordEnd != null && wordEnd > _offset) {
        _showWord(_offset, wordEnd);
      } else {
        _showPassage(scroll: true);
      }
    }
    notifyListeners();
    _persist(
      preferences.saveFollow(value),
      'saving the reading-follow preference failed',
    );
  }

  /// Asks the page to bring the passage being read back into view - after
  /// the reader scrolled away from it and asked to return. Nothing happens
  /// while stopped or with following turned off.
  void revealPosition() {
    if (_disposed ||
        !follow ||
        phase == ReadAloudPhase.idle ||
        _activeIndex >= document.chunks.length) {
      return;
    }
    final chunk = document.chunks[_activeIndex];
    onFollowScroll?.call(chunk.blockIndex, chunk.blockOffset + _offset);
  }

  /// Select one installed voice for all passages requesting [language]. Null
  /// returns that language to the operating-system default. A stale ID or an
  /// ID for another language is ignored rather than being passed to native TTS.
  void setPreferredVoice(String language, String? voiceId) {
    if (_disposed) return;
    final normalizedLanguage = normalizeSpeechLanguage(language);
    if (normalizedLanguage.isEmpty) return;
    final normalizedVoiceId = sanitizeSpeechVoiceId(voiceId);
    final choices = voiceChoices[normalizedLanguage] ?? const <SpeechVoice>[];
    if (normalizedVoiceId != null &&
        !choices.any((voice) => voice.id == normalizedVoiceId)) {
      return;
    }
    if (_settings.preferredVoiceIdFor(normalizedLanguage) ==
        normalizedVoiceId) {
      return;
    }
    _settingsVersion++;
    _settings = _settings.withPreferredVoice(
      normalizedLanguage,
      normalizedVoiceId,
    );
    notifyListeners();
    _persist(
      preferences.savePreferredVoice(normalizedLanguage, normalizedVoiceId),
      'saving the reading voice preference failed',
    );
    if (phase == ReadAloudPhase.playing &&
        _activeIndex < document.chunks.length &&
        normalizeSpeechLanguage(
              speechLanguage(
                document.chunks[_activeIndex].text,
                fallbackLanguage,
              ),
            ) ==
            normalizedLanguage) {
      _speakCurrent();
    }
  }

  /// Selecting a timer never starts playback by itself. The deadline continues
  /// while paused, matching a real sleep timer; stop, finish, a route change
  /// and disposal clear it so it cannot affect another article.
  void setSleepTimer(ReadAloudSleepTimerOption option) {
    if (_disposed) return;
    _sleepTimer.select(option, _onSleepTimerExpired);
    notifyListeners();
  }

  void _onSleepTimerExpired() {
    if (_disposed) return;
    _stop(ReadAloudNotice.sleepTimerFinished, clearSleepTimer: false);
  }

  void previewSeek(double value) {
    if (phase == ReadAloudPhase.idle || _disposed) return;
    _preview = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void cancelSeek() {
    if (_preview == null || _disposed) return;
    _preview = null;
    notifyListeners();
  }

  void commitSeek(double value) {
    if (phase == ReadAloudPhase.idle || _disposed) return;
    _preview = null;
    final ratio = value.clamp(0.0, 1.0);
    if (ratio >= 1) {
      _finish();
      return;
    }
    final target = (ratio * document.totalLength).floor();
    var index = document.chunks.length - 1;
    for (var i = 0; i < document.chunks.length; i++) {
      final chunk = document.chunks[i];
      if (target < chunk.start + chunk.text.length) {
        index = i;
        break;
      }
    }
    _activeIndex = index;
    final chunk = document.chunks[index];
    _offset = safeSpeechOffset(chunk.text, target - chunk.start);
    _wordEnd = null;
    _setActualProgress();
    if (phase == ReadAloudPhase.playing) {
      _speakCurrent(scroll: true);
    } else {
      _showPassage(scroll: true);
      notifyListeners();
    }
  }

  void _performStop(int run, ReadAloudPhase expected) {
    unawaited(
      coordinator
          .perform(
            this,
            () => !_disposed && _run == run && phase == expected,
            (engine, valid) => engine.stop(),
          )
          .catchError((Object error, StackTrace stack) {
            if (!_disposed && _run == run) _fail();
          }),
    );
  }

  void _speakCurrent({bool scroll = false}) {
    if (_disposed || phase != ReadAloudPhase.playing) return;
    if (_activeIndex >= document.chunks.length) {
      _finish();
      return;
    }
    final chunk = document.chunks[_activeIndex];
    if (_offset >= chunk.text.length) {
      _activeIndex++;
      _offset = 0;
      _speakCurrent(scroll: scroll);
      return;
    }
    final run = ++_run;
    final id = coordinator.nextUtteranceId();
    _utteranceId = id;
    final offset = _offset;
    _offsetAtStart = offset;
    _wordEnd = null;
    final language = speechLanguage(chunk.text, fallbackLanguage);
    final voice = resolvedVoiceFor(language);
    _setActualProgress();
    _showPassage(scroll: scroll);
    notifyListeners();
    unawaited(
      coordinator
          .perform(
            this,
            () => !_disposed && _run == run && phase == ReadAloudPhase.playing,
            (engine, valid) async {
              // Pause/seek/rate/voice changes all cancel the old platform
              // utterance. Recheck after every await before using shared TTS.
              await engine.stop();
              if (!valid()) return;
              await engine.speak(
                utteranceId: id,
                text: chunk.text.substring(offset),
                language: language,
                voice: voice,
                rate: speed,
              );
            },
          )
          .catchError((Object error, StackTrace stack) {
            if (!_disposed && _run == run) _fail();
          }),
    );
  }

  void _onSpeechEvent(SpeechEvent event) {
    if (_disposed ||
        phase != ReadAloudPhase.playing ||
        event.utteranceId != _utteranceId) {
      return;
    }
    switch (event.type) {
      case SpeechEventType.started:
        return;
      case SpeechEventType.cancelled:
        _fail();
        return;
      case SpeechEventType.range:
        final chunk = document.chunks[_activeIndex];
        final remaining = chunk.text.length - _offsetAtStart;
        if (event.start < 0 ||
            event.end <= event.start ||
            event.start >= remaining) {
          return;
        }
        final nextOffset = speechCodePointBoundary(
          chunk.text,
          _offsetAtStart + event.start,
        );
        if (nextOffset < _offset) return;
        _offset = nextOffset;
        final end = speechCodePointBoundary(
          chunk.text,
          _offsetAtStart + event.end,
          end: true,
        );
        _wordEnd = end;
        _setActualProgress();
        _showWord(_offset, end);
        notifyListeners();
        return;
      case SpeechEventType.completed:
        _activeIndex++;
        _offset = 0;
        _speakCurrent(scroll: true);
        return;
      case SpeechEventType.error:
        _fail();
        return;
    }
  }

  int _offsetAtStart = 0;

  Iterable<String> _spokenLanguages() sync* {
    final values = <String>{};
    for (final chunk in document.chunks) {
      final language = normalizeSpeechLanguage(
        speechLanguage(chunk.text, fallbackLanguage),
      );
      if (language.isNotEmpty && values.add(language)) yield language;
    }
  }

  void _setActualProgress() {
    if (_activeIndex >= document.chunks.length) {
      _progress = 1;
    } else {
      final chunk = document.chunks[_activeIndex];
      _progress = (chunk.start + _offset) / document.totalLength;
    }
  }

  void _showPassage({bool scroll = false}) {
    if (!follow || _activeIndex >= document.chunks.length) return;
    final chunk = document.chunks[_activeIndex];
    final block = document.blocks[chunk.blockIndex];
    _mark(
      chunk.blockIndex,
      ReadAloudHighlight(0, block.text.length, wholeBlock: true),
    );
    if (scroll && _preview == null) {
      onFollowScroll?.call(chunk.blockIndex, chunk.blockOffset + _offset);
    }
  }

  void _showWord(int from, int to) {
    if (!follow || _activeIndex >= document.chunks.length) return;
    final chunk = document.chunks[_activeIndex];
    _mark(
      chunk.blockIndex,
      ReadAloudHighlight(chunk.blockOffset + from, chunk.blockOffset + to),
    );
    if (_preview == null) {
      onFollowScroll?.call(chunk.blockIndex, chunk.blockOffset + from);
    }
  }

  void _mark(int index, ReadAloudHighlight highlight) {
    if (_markedBlock != null && _markedBlock != index) {
      highlights[_markedBlock!].value = null;
    }
    _markedBlock = index;
    highlights[index].value = highlight;
  }

  void _clearHighlight() {
    if (_markedBlock != null) highlights[_markedBlock!].value = null;
    _markedBlock = null;
  }

  void _finish() {
    _run++;
    _utteranceId = null;
    phase = ReadAloudPhase.idle;
    notice = ReadAloudNotice.finished;
    _activeIndex = document.chunks.length;
    _offset = 0;
    _preview = null;
    _progress = 1;
    _sleepTimer.clear();
    _clearHighlight();
    notifyListeners();
    _release();
  }

  void _fail() {
    _run++;
    _utteranceId = null;
    phase = ReadAloudPhase.idle;
    notice = ReadAloudNotice.error;
    _activeIndex = 0;
    _offset = 0;
    _preview = null;
    _progress = 0;
    _sleepTimer.clear();
    _clearHighlight();
    notifyListeners();
    _release();
  }

  void _persist(Future<void> pending, String message) {
    unawaited(
      pending.catchError((Object error, StackTrace stack) {
        AppLogger.debug(message);
      }),
    );
  }

  void _release() {
    unawaited(
      coordinator.release(this).catchError((Object error, StackTrace stack) {
        AppLogger.debug('stopping device speech failed');
      }),
    );
  }

  @override
  void speechWasReplaced() {
    if (_disposed) return;
    _run++;
    _utteranceId = null;
    phase = ReadAloudPhase.idle;
    notice = ReadAloudNotice.stopped;
    _activeIndex = 0;
    _offset = 0;
    _preview = null;
    _progress = 0;
    _sleepTimer.clear();
    _clearHighlight();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _utteranceId = null;
    _sleepTimer.dispose();
    _release();
    unawaited(_subscription.cancel());
    for (final highlight in highlights) {
      highlight.dispose();
    }
    super.dispose();
  }
}
