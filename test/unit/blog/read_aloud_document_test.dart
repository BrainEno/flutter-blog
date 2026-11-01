import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reads title and visible Markdown in order without URLs or duplicate lists',
    () {
      final document = ReadAloudDocument.parse('题目', '''
# Heading

Hello **bold** [link](https://example.invalid/secret) and `inline`.

- parent
  - nested

> quotation

```
code sample
```

![not spoken](https://example.invalid/image.png)
''');
      final spoken = document.chunks.map((chunk) => chunk.text).join('\n');
      expect(spoken, startsWith('题目\nHeading\nHello'));
      for (final value in [
        'bold',
        'link',
        'inline',
        'parent',
        'nested',
        'quotation',
        'code sample',
      ]) {
        expect(spoken, contains(value));
      }
      expect(RegExp('nested').allMatches(spoken), hasLength(1));
      expect(spoken, isNot(contains('https:')));
      expect(spoken, isNot(contains('not spoken')));
      expect(document.hasBody, isTrue);
    },
  );

  test(
    'tight list inline formatting stays in one passage without duplicating nested items',
    () {
      final document = ReadAloudDocument.parse(
        'Title',
        '- A **bold** [link](https://example.invalid)\n  - nested',
      );
      final passages = document.chunks.map((chunk) => chunk.text).toList();
      expect(passages, contains('A bold link'));
      expect(passages.where((text) => text.contains('nested')), hasLength(1));
    },
  );

  test('empty and image-only bodies do not expose narration', () {
    expect(ReadAloudDocument.parse('Title', '').hasBody, isFalse);
    expect(
      ReadAloudDocument.parse(
        'Title',
        '![description](https://example.invalid/a.png)',
      ).hasBody,
      isFalse,
    );
    expect(
      ReadAloudDocument.parse('Title', '```\nvisible code\n```').hasBody,
      isTrue,
    );
  });

  test('chunks are bounded by Unicode scalars and retain UTF-16 mappings', () {
    final body = '${'😀' * 235}。 ${'A' * 300}\n\n末尾';
    final document = ReadAloudDocument.parse('Title', body);
    for (final chunk in document.chunks) {
      expect(chunk.text.runes.length, lessThanOrEqualTo(220));
      final block = document.blocks[chunk.blockIndex];
      expect(
        block.text.substring(
          chunk.blockOffset,
          chunk.blockOffset + chunk.text.length,
        ),
        chunk.text,
      );
      final units = chunk.text.codeUnits;
      expect(units.first, isNot(inInclusiveRange(0xdc00, 0xdfff)));
      expect(units.last, isNot(inInclusiveRange(0xd800, 0xdbff)));
    }
    expect(document.chunks.last.text, '末尾');
    expect(
      document.totalLength,
      document.chunks.fold<int>(0, (sum, chunk) => sum + chunk.text.length),
    );
  });

  test('spoken positions account for inline code and images in a RichText', () {
    final document = ReadAloudDocument.parse(
      'T',
      'left`code`right ![alt](https://example.invalid/a.png) end',
    );
    final block = document.blocks.singleWhere(
      (block) => block.text.contains('left'),
    );
    expect(block.text, 'leftcoderight  end');
    expect(block.visualOffset(4), 4); // The inline code WidgetSpan.
    expect(block.visualOffset(8), 5); // Text following the WidgetSpan.
    expect(
      block.visualOffset(block.text.indexOf('end')),
      'left'.length + 1 + 'right '.length + 1 + 1,
    );
  });

  test('seeks avoid surrogate splits and the middle of Latin words', () {
    expect(safeSpeechOffset('Hi 😀 world', 4), 3);
    expect(speechCodePointBoundary('Hi 😀 world', 4, end: true), 5);
    expect(safeSpeechOffset('zero astronaut', 9), 5);
    expect(safeSpeechOffset('你好世界', 2), 2);
    expect(safeSpeechOffset('abc', -8), 0);
    expect(safeSpeechOffset('abc', 100), 3);
  });

  test(
    'language and voice are selected per chunk with exact then family fallback',
    () {
      expect(speechLanguage('中文与 English', 'en'), 'en');
      expect(speechLanguage('中文中文 English', 'en'), 'zh-CN');
      expect(speechLanguage('123!?', 'zh-TW'), 'zh-TW');
      const voices = [
        SpeechVoice(id: 'tw', language: 'zh-TW'),
        SpeechVoice(id: 'cn', language: 'zh-CN'),
        SpeechVoice(id: 'us', language: 'en-US'),
      ];
      expect(matchingSpeechVoice(voices, 'zh-cn')?.id, 'cn');
      expect(matchingSpeechVoice(voices, 'en')?.id, 'us');
      expect(matchingSpeechVoice(voices, 'fr'), isNull);
    },
  );
}
