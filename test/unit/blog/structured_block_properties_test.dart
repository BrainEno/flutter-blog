import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_block_properties.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

StructuredArticleDraft _body() {
  final article = structuredArticle();
  return StructuredArticleDraft.parse(
    version: article['contentBlocksVersion'],
    blocks: article['contentBlocks'],
  );
}

void main() {
  test('image preserves URL and differentiates missing and empty caption', () {
    final body = _body();
    final changed = StructuredImageProperties(
      body: body,
      blockId: 'image-one',
      alt: 'Alt 🐈',
      captionPresent: true,
      caption: '',
    ).apply(body);
    expect(changed.blocks[1], {
      'id': 'image-one',
      'type': 'image',
      'src': '/media/one.png',
      'alt': 'Alt 🐈',
      'caption': '',
    });
    expect(changed.blocks.first, body.blocks.first);
    expect(body.blocks[1]['caption'], 'First caption');
    final removed = StructuredImageProperties(
      body: changed,
      blockId: 'image-one',
      alt: 'Alt 🐈',
      captionPresent: false,
      caption: 'ignored',
    ).apply(changed);
    expect(removed.blocks[1].containsKey('caption'), isFalse);
  });

  test('quote heading and list changes retain runs and text', () {
    final body = _body();
    final quote = StructuredQuoteProperties(
      body: body,
      blockId: 'quote',
      attributionPresent: false,
      attribution: '',
    ).apply(body);
    expect(quote.blocks[3].containsKey('attribution'), isFalse);
    expect(quote.blocks[3]['inlines'], body.blocks[3]['inlines']);
    final heading = StructuredHeadingProperties(
      body: quote,
      blockId: 'heading',
      level: 4,
    ).apply(quote);
    expect(heading.blocks[0]['inlines'], body.blocks[0]['inlines']);
    final list = StructuredListProperties(
      body: heading,
      blockId: 'list',
      ordered: false,
    ).apply(heading);
    expect(list.blocks[4]['itemInlines'], body.blocks[4]['itemInlines']);
    expect(list.blocks[4]['items'], body.blocks[4]['items']);
    expect(list.blocks[4]['ordered'], false);
  });

  test('code is literal and invalid schema or UTF-16 cannot change body', () {
    final body = _body();
    final changed = StructuredCodeProperties(
      body: body,
      blockId: 'code',
      language: 'dart',
      code: '  x\n\n',
    ).apply(body);
    expect(changed.blocks.last['code'], '  x\n\n');
    expect(
      () => StructuredCodeProperties(
        body: body,
        blockId: 'code',
        language: '',
        code: 'x',
      ).apply(body),
      throwsFormatException,
    );
    expect(
      () => StructuredCodeProperties(
        body: body,
        blockId: 'code',
        language: 'dart',
        code: String.fromCharCode(0xd800),
      ).apply(body),
      throwsFormatException,
    );
    expect(body.blocks.last['code'], '  a\n\n b  \n');
  });

  test('selection requires identical snapshot and matching block kind', () {
    final body = _body();
    final sameValue = _body();
    final edit = StructuredListProperties(
      body: body,
      blockId: 'list',
      ordered: false,
    );
    expect(() => edit.apply(sameValue), throwsStateError);
    expect(
      () => StructuredListProperties(
        body: body,
        blockId: 'heading',
        ordered: false,
      ).apply(body),
      throwsStateError,
    );
    expect(
      () => StructuredHeadingProperties(
        body: body,
        blockId: 'heading',
        level: 5,
      ).apply(body),
      throwsFormatException,
    );
  });
}
