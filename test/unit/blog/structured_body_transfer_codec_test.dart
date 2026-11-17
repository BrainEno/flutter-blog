import 'dart:convert';

import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_body_transfer_codec.dart';
import 'package:belog/features/blog/domain/editing/structured_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

StructuredArticleDraft sample(int version, String text) =>
    StructuredArticleDraft.parse(
      version: version,
      blocks: [
        {'id': 'p', 'type': 'paragraph', 'text': text},
        {'id': 'q', 'type': 'quote', 'text': 'quoted', 'attribution': ''},
        {
          'id': 'l',
          'type': 'list',
          'ordered': false,
          'items': ['one', 'two'],
        },
        {'id': 'c', 'type': 'code', 'language': 'dart', 'code': 'a\nb'},
      ],
    );

void main() {
  test(
    'v0 and v1 exact round trip, including unusual UTF-16 and whitespace',
    () {
      for (final version in [0, 1]) {
        final before = sample(
          version,
          '中🚀\n\t ${String.fromCharCode(0xd800)} \\ "',
        );
        final encoded = StructuredBodyTransferCodec.encode(before);
        expect(encoded.codeUnits.every((unit) => unit <= 127), isTrue);
        final after = StructuredBodyTransferCodec.decode(encoded);
        expect(
          StructuredDocumentComparison.between(before, after).hasChanges,
          isFalse,
        );
        expect(StructuredBodyTransferCodec.encode(after), encoded);
      }
    },
  );
  test('inline marks and optional fields survive verbatim', () {
    final body = StructuredArticleDraft.parse(
      version: 1,
      blocks: [
        {
          'id': 'p',
          'type': 'paragraph',
          'text': 'ab',
          'inlines': [
            {
              'text': 'a',
              'marks': ['bold'],
            },
            {'text': 'b', 'href': 'https://example.com'},
          ],
        },
      ],
    );
    final decoded = StructuredBodyTransferCodec.decode(
      StructuredBodyTransferCodec.encode(body),
    );
    expect(
      StructuredDocumentComparison.between(body, decoded).hasChanges,
      isFalse,
    );
  });
  test('rejects wrong envelope, schema, malformed and noncanonical input', () {
    final canonical = StructuredBodyTransferCodec.encode(sample(1, 'hello'));
    final obj = jsonDecode(canonical) as Map<String, dynamic>;
    final wrongSchema = {...obj, 'schema': 2};
    final extra = {...obj, 'unknown': true};
    final wrongVersion = {...obj, 'contentBlocksVersion': 99};
    final duplicates = canonical.replaceFirst('{', '{"schema":1,');
    for (final text in [
      '',
      ' ',
      '{',
      '$canonical ',
      duplicates,
      jsonEncode(wrongSchema),
      jsonEncode(extra),
      jsonEncode(wrongVersion),
      canonical.replaceFirst('hello', 'héllo'),
    ]) {
      expect(
        () => StructuredBodyTransferCodec.decode(text),
        throwsFormatException,
        reason: text,
      );
    }
  });
  test('rejects malformed block, duplicate IDs and size excess', () {
    final canonical = StructuredBodyTransferCodec.encode(sample(1, 'hello'));
    final obj = jsonDecode(canonical) as Map<String, dynamic>;
    for (final blocks in [
      [
        {'id': 'x', 'type': 'mystery'},
      ],
      [
        {'id': 'x', 'type': 'paragraph', 'text': 'a'},
        {'id': 'x', 'type': 'paragraph', 'text': 'b'},
      ],
      <Object>[],
    ]) {
      expect(
        () => StructuredBodyTransferCodec.decode(
          jsonEncode({...obj, 'contentBlocks': blocks}),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => StructuredBodyTransferCodec.decode(
        'x' * (StructuredBodyTransferCodec.maxEncodedLength + 1),
      ),
      throwsFormatException,
    );
  });
}
