import 'dart:async';

import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/read_aloud_fakes.dart';

ReadAloudController makeReader(
  FakeSpeechEngine engine,
  FakeReadAloudPreferences preferences, {
  SpeechCoordinator? coordinator,
  String title = 'Title',
  String body = 'Hello world again.\n\n中文段落。',
  void Function(int, int)? scroll,
}) => ReadAloudController(
  document: ReadAloudDocument.parse(title, body),
  coordinator: coordinator ?? SpeechCoordinator(engine),
  preferences: preferences,
  fallbackLanguage: 'en',
  onFollowScroll: scroll,
);

void main() {
  test(
    'play, boundary, pause, resume, speed and stale events stay coherent',
    () async {
      final engine = FakeSpeechEngine();
      final preferences = FakeReadAloudPreferences();
      final scrolls = <(int, int)>[];
      final reader = makeReader(
        engine,
        preferences,
        scroll: (i, p) => scrolls.add((i, p)),
      );
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await reader.initialize();
      expect(reader.available, isTrue);
      expect(reader.follow, isTrue);
      reader.togglePlayback();
      await flushSpeech();
      expect(engine.calls.single.text, 'Title');
      expect(engine.calls.single.voice?.id, 'english');
      expect(reader.highlights[0].value?.wholeBlock, isTrue);
      expect(scrolls.last.$1, 0);

      final titleId = engine.calls.last.id;
      engine.event(titleId, SpeechEventType.completed);
      await flushSpeech();
      expect(engine.calls.last.text, 'Hello world again.');
      final bodyId = engine.calls.last.id;
      engine.event(bodyId, SpeechEventType.range, start: 6, end: 11);
      expect(reader.highlights[0].value, isNull);
      expect(reader.highlights[1].value?.start, 6);
      expect(reader.highlights[1].value?.end, 11);
      expect(
        reader.progress,
        closeTo((5 + 6) / reader.document.totalLength, 0.0001),
      );
      expect(scrolls.last, (1, 6));
      engine.event(bodyId, SpeechEventType.range, start: 0, end: 5);
      expect(reader.highlights[1].value?.start, 6); // out-of-order boundary

      reader.togglePlayback();
      await flushSpeech();
      expect(reader.phase, ReadAloudPhase.paused);
      expect(reader.highlights[1].value?.start, 6);
      engine.event(bodyId, SpeechEventType.completed); // stopped utterance
      expect(reader.phase, ReadAloudPhase.paused);
      reader.togglePlayback();
      await flushSpeech();
      final resumed = engine.calls.last;
      expect(resumed.id, isNot(bodyId));
      expect(resumed.text, 'world again.');
      engine.event(bodyId, SpeechEventType.completed); // stale after resume
      expect(reader.phase, ReadAloudPhase.playing);
      engine.event(resumed.id, SpeechEventType.range, start: 0, end: 5);
      expect(reader.highlights[1].value?.start, 6);
      reader.setSpeed(1.5);
      await flushSpeech();
      expect(engine.calls.last.text, 'world again.');
      expect(engine.calls.last.rate, 1.5);
      engine.event(resumed.id, SpeechEventType.error);
      expect(reader.phase, ReadAloudPhase.playing);

      engine.event(engine.calls.last.id, SpeechEventType.completed);
      await flushSpeech();
      expect(engine.calls.last.text, '中文段落。');
      expect(engine.calls.last.language, 'zh-CN');
      expect(engine.calls.last.voice?.id, 'chinese');
      engine.event(engine.calls.last.id, SpeechEventType.completed);
      await flushSpeech();
      expect(reader.phase, ReadAloudPhase.idle);
      expect(reader.notice, ReadAloudNotice.finished);
      expect(reader.progress, 1);
      expect(reader.highlights.every((value) => value.value == null), isTrue);
    },
  );

  test(
    'scrub previews without restarting, commits safely, and paused seek stays silent',
    () async {
      final engine = FakeSpeechEngine();
      final reader = makeReader(
        engine,
        FakeReadAloudPreferences(),
        title: '',
        body: 'zero astronaut 🚀 end',
      );
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await reader.initialize();
      reader.togglePlayback();
      await flushSpeech();
      final first = engine.calls.last;
      reader.previewSeek(0.7);
      expect(reader.progress, 0.7);
      expect(engine.calls, hasLength(1));
      reader.cancelSeek();
      expect(reader.progress, 0);
      reader.commitSeek(9 / reader.document.totalLength);
      await flushSpeech();
      expect(engine.calls.last.text, startsWith('astronaut'));
      expect(engine.calls.last.id, isNot(first.id));

      reader.togglePlayback();
      await flushSpeech();
      final count = engine.calls.length;
      reader.commitSeek(2 / reader.document.totalLength);
      reader.setSpeed(2);
      await flushSpeech();
      expect(reader.phase, ReadAloudPhase.paused);
      expect(engine.calls, hasLength(count));
      reader.togglePlayback();
      await flushSpeech();
      expect(engine.calls.last.text, startsWith('zero'));
      expect(engine.calls.last.rate, 2);
      reader.commitSeek(1);
      await flushSpeech();
      expect(reader.notice, ReadAloudNotice.finished);
      expect(reader.progress, 1);
    },
  );

  test(
    'follow can be toggled, persisted, and falls back to the passage',
    () async {
      final engine = FakeSpeechEngine();
      final preferences = FakeReadAloudPreferences();
      final reader = makeReader(
        engine,
        preferences,
        title: '',
        body: 'Hello world',
      );
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await reader.initialize();
      reader.togglePlayback();
      await flushSpeech();
      expect(reader.highlights[1].value?.wholeBlock, isTrue);
      reader.setFollow(false);
      await flushSpeech();
      expect(reader.highlights[1].value, isNull);
      engine.event(
        engine.calls.last.id,
        SpeechEventType.range,
        start: 6,
        end: 11,
      );
      expect(reader.highlights[1].value, isNull);
      reader.setFollow(true);
      await flushSpeech();
      expect(reader.highlights[1].value?.start, 6);
      expect(reader.highlights[1].value?.end, 11);
      expect(preferences.writes, [false, true]);
      reader.stop();
      await flushSpeech();
      expect(reader.notice, ReadAloudNotice.stopped);
      expect(reader.progress, 0);
      expect(reader.highlights[1].value, isNull);
    },
  );

  test(
    'storage failures keep default behavior and a late load cannot undo a choice',
    () async {
      final engine = FakeSpeechEngine();
      final preferences = FakeReadAloudPreferences()
        ..loadGate = Completer<bool>();
      final reader = makeReader(engine, preferences);
      addTearDown(() async {
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      final initialization = reader.initialize();
      reader.setFollow(false);
      preferences.loadGate!.complete(true);
      await initialization;
      expect(reader.follow, isFalse);
      preferences.failSave = true;
      reader.setFollow(true);
      await flushSpeech();
      expect(reader.follow, isTrue);
    },
  );

  test(
    'unsupported and empty documents stay hidden; playback errors can retry',
    () async {
      final engine = FakeSpeechEngine()..unsupported = true;
      final coordinator = SpeechCoordinator(engine);
      final empty = makeReader(
        engine,
        FakeReadAloudPreferences(),
        coordinator: coordinator,
        body: '',
      );
      final reader = makeReader(
        engine,
        FakeReadAloudPreferences(),
        coordinator: coordinator,
      );
      addTearDown(() async {
        empty.dispose();
        reader.dispose();
        await flushSpeech();
        await engine.close();
      });
      await empty.initialize();
      expect(empty.available, isFalse);
      expect(engine.initializationCount, 0);
      await reader.initialize();
      expect(reader.available, isFalse);
      engine.unsupported = false;
      await reader.initialize(); // a new capability check can recover
      expect(reader.available, isTrue);
      engine.failSpeak = true;
      reader.togglePlayback();
      await flushSpeech();
      expect(reader.notice, ReadAloudNotice.error);
      expect(reader.phase, ReadAloudPhase.idle);
      engine.failSpeak = false;
      reader.togglePlayback();
      await flushSpeech();
      expect(reader.phase, ReadAloudPhase.playing);
      expect(engine.calls, hasLength(1));
    },
  );

  test(
    'ownership and serialized commands isolate replaced or disposed pages',
    () async {
      final engine = FakeSpeechEngine()..stopGate = Completer<void>();
      final coordinator = SpeechCoordinator(engine);
      final preferences = FakeReadAloudPreferences();
      final first = makeReader(
        engine,
        preferences,
        coordinator: coordinator,
        title: 'First',
      );
      final second = makeReader(
        engine,
        preferences,
        coordinator: coordinator,
        title: 'Second',
      );
      addTearDown(() async {
        second.dispose();
        await flushSpeech();
        await engine.close();
      });
      await first.initialize();
      await second.initialize();
      expect(engine.initializationCount, 1);
      first.togglePlayback();
      await flushSpeech(); // first stop is still in flight
      second.togglePlayback();
      expect(first.notice, ReadAloudNotice.stopped);
      first.dispose(); // must not stop the new owner
      engine.stopGate!.complete();
      await flushSpeech();
      expect(engine.calls.map((call) => call.text), ['Second']);
      expect(second.phase, ReadAloudPhase.playing);
      final stopsBefore = engine.stopCount;
      await coordinator.stopIfCurrent(first); // stale route callback
      await flushSpeech();
      expect(engine.stopCount, stopsBefore);
      expect(second.phase, ReadAloudPhase.playing);
      await coordinator.stopIfCurrent(second);
      expect(second.notice, ReadAloudNotice.stopped);
    },
  );
}
