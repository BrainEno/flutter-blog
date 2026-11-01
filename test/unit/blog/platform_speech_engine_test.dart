import 'package:belog/features/blog/data/read_aloud/platform_speech_engine.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('belog/read_aloud');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test(
    'platform contract includes utterance IDs, UTF-16 ranges and explicit language',
    () async {
      final outgoing = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        outgoing.add(call);
        switch (call.method) {
          case 'initialize':
            return {
              'available': true,
              'voices': [
                {'id': 'voice-en', 'language': 'en-US'},
                {'id': 42, 'language': 'bad'},
              ],
            };
          case 'speak':
            return true;
          case 'stop':
            return null;
        }
        return null;
      });
      final engine = PlatformSpeechEngine(channel: channel);
      final voices = await engine.initialize();
      expect(voices, hasLength(1));
      expect(voices.single.id, 'voice-en');
      await engine.speak(
        utteranceId: 'read-1',
        text: 'Hello 😀',
        language: 'en',
        voice: voices.single,
        rate: 1.25,
      );
      final args = outgoing.last.arguments as Map;
      expect(args['id'], 'read-1');
      expect(args['text'], 'Hello 😀');
      expect(args['language'], 'en');
      expect(args['voice'], 'voice-en');
      expect(args['rate'], 1.25);

      final received = <SpeechEvent>[];
      final subscription = engine.events.listen(received.add);
      Future<void> send(Map<String, Object> event) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('event', event),
          ),
          null,
        );
      }

      await send({'id': 'read-1', 'type': 'range', 'start': 6, 'end': 8});
      await send({'id': 'old', 'type': 'completed'});
      await send({'id': 'read-1', 'type': 'unknown'});
      expect(received, hasLength(2));
      expect(received.first.type, SpeechEventType.range);
      expect(received.first.start, 6);
      expect(received.first.end, 8);
      expect(received.last.utteranceId, 'old');
      await engine.stop();
      expect(outgoing.last.method, 'stop');
      await subscription.cancel();
    },
  );

  test('unsupported initialization and rejected speech are reported', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return {'available': false};
      return false;
    });
    final engine = PlatformSpeechEngine(channel: channel);
    await expectLater(engine.initialize(), throwsUnsupportedError);
    await expectLater(
      engine.speak(
        utteranceId: '1',
        text: 'A',
        language: 'en',
        voice: null,
        rate: 1,
      ),
      throwsStateError,
    );
  });
}
