import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings canonicalize safe local language and voice values', () {
    final settings = ReadAloudSettings(
      follow: false,
      speed: 3,
      preferredVoiceIds: const {
        'EN_us': ' English ',
        'bad tag!': 'ignored',
        'zh-cn': '\u0007ignored',
      },
    );
    expect(settings.follow, isFalse);
    expect(settings.speed, 1);
    expect(settings.preferredVoiceIds, {'en-US': 'English'});
    expect(settings.preferredVoiceIdFor('en-US'), 'English');
    expect(
      settings.withPreferredVoice('en-US', null).preferredVoiceIds,
      isEmpty,
    );
    expect(normalizeSpeechLanguage(' zh_hans_cn '), 'zh-Hans-CN');
    expect(normalizeSpeechLanguage('1-no'), isEmpty);
    expect(sanitizeSpeechVoiceId('voice\nname'), isNull);
  });

  test(
    'voice groups include only article languages and deterministic choices',
    () {
      const voices = [
        SpeechVoice(id: 'en-gb', language: 'en-GB', displayName: 'Zed'),
        SpeechVoice(id: 'en-us', language: 'en-US', displayName: 'Able'),
        SpeechVoice(id: 'zh', language: 'zh', displayName: 'Chinese'),
        SpeechVoice(id: 'en-us', language: 'en-US', displayName: 'Duplicate'),
      ];
      final groups = speechVoiceChoicesForLanguages([
        'en',
        'zh-CN',
        'fr',
      ], voices);
      expect(groups.keys, ['en', 'zh-CN']);
      expect(groups['en']!.map((voice) => voice.id), ['en-us', 'en-gb']);
      expect(groups['zh-CN']!.single.id, 'zh');
    },
  );

  test(
    'a selected installed compatible voice wins, stale choice falls back',
    () {
      const voices = [
        SpeechVoice(id: 'en-us', language: 'en-US'),
        SpeechVoice(id: 'en-gb', language: 'en-GB'),
      ];
      final selected = ReadAloudSettings(
        follow: true,
        speed: 1,
        preferredVoiceIds: const {'en': 'en-gb'},
      );
      expect(
        resolveSpeechVoice(
          voices: voices,
          language: 'en',
          settings: selected,
        )?.id,
        'en-gb',
      );
      final stale = selected.withPreferredVoice('en', 'missing');
      expect(
        resolveSpeechVoice(
          voices: voices,
          language: 'en-US',
          settings: stale,
        )?.id,
        'en-us',
      );
    },
  );
}
