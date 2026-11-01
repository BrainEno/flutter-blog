import 'dart:convert';

import 'package:belog/features/blog/data/datasources/article_document_codec.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/structured_article_fixtures.dart';

void main() {
  test('v1 decodes every block, exact runs and image metadata', () {
    final article = structuredArticle();
    final model = BlogModel.fromNowaveArticle(article);
    final document = model.document!;
    expect(document.supported, isTrue);
    expect(document.version, 1);
    expect(document.blocks, hasLength(7));
    expect(document.hasImages, isTrue);
    final heading = document.blocks.first as ArticleTextBlock;
    expect(heading.kind, ArticleTextKind.heading);
    expect(heading.level, 2);
    expect(heading.runs.map((r) => r.text).join(), 'Bold代码');
    expect(heading.runs.first.marks, {
      ArticleInlineMark.bold,
      ArticleInlineMark.italic,
      ArticleInlineMark.underline,
      ArticleInlineMark.strikethrough,
    });
    expect(heading.runs.first.href, '/guide');
    expect(heading.runs.last.marks, contains(ArticleInlineMark.code));
    final quote = document.blocks[3] as ArticleTextBlock;
    expect(quote.attribution, 'Author name');
    final list = document.blocks[4] as ArticleListBlock;
    expect(list.ordered, isTrue);
    expect(list.items.last.text, ' second item ');
    expect(list.items.last.runs.single.text, ' second item ');
    final image = document.blocks[1] as ArticleImageBlock;
    expect(image.src, '/media/one.png');
    expect(image.alt, 'First image alt');
    expect(image.caption, 'First caption');
    final code = document.blocks.last as ArticleCodeBlock;
    expect(code.language, 'dart');
    expect(code.code, '  a\n\n b  \n');
    expect(model.plainEditorCompatible, isFalse);
    expect(model.documentJson, isNotNull);
    expect(jsonDecode(model.documentJson!)['blocks'], article['contentBlocks']);
  });

  test('simple v0 keeps legacy Markdown and complex v0 is structured', () {
    const paragraph = {'id': 'p', 'type': 'paragraph', 'text': '# Markdown'};
    final simple = BlogModel.fromNowaveArticle({
      'contentBlocksVersion': 0,
      'contentBlocks': [paragraph],
    });
    expect(simple.document, isNull);
    expect(simple.documentJson, isNull);
    expect(simple.content, '# Markdown');
    expect(simple.plainEditorCompatible, isTrue);

    final complex = BlogModel.fromNowaveArticle({
      'contentBlocksVersion': 0,
      'contentBlocks': [
        {'id': 'q', 'type': 'quote', 'text': 'text', 'attribution': 'name'},
        {'id': 'h', 'type': 'heading', 'level': 3, 'text': 'Heading'},
        {
          'id': 'l',
          'type': 'list',
          'ordered': false,
          'items': ['x', 'y'],
        },
      ],
    });
    expect(complex.document?.supported, isTrue);
    expect(complex.document?.blocks, hasLength(3));
    expect(complex.plainEditorCompatible, isFalse);
  });

  test('model copies retain the document only while body is unchanged', () {
    final model = BlogModel.fromNowaveArticle(structuredArticle());
    expect(model.copyWith(title: 'renamed').document, same(model.document));
    expect(
      model.copyWith(content: model.content).documentJson,
      model.documentJson,
    );
    expect(model.copyWith(content: 'different').document, isNull);
    expect(model.copyWith(content: 'different').documentJson, isNull);
  });

  test('unknown and malformed documents are explicit and fail closed', () {
    final invalid = <Map<String, Object?>>[
      {
        'version': 7,
        'blocks': [
          {'type': 'future', 'id': 'x'},
        ],
      },
      {'version': '1', 'blocks': []},
      {'version': 1, 'blocks': null},
      {
        'version': 1,
        'blocks': [17],
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'p', 'type': 'paragraph', 'text': 4},
        ],
      },
      {
        'version': 0,
        'blocks': [
          {'id': 'p', 'type': 'paragraph', 'text': 'x', 'future': true},
        ],
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'x', 'type': 'heading', 'level': 1, 'text': 'x'},
        ],
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'x', 'type': 'image', 'src': '//evil.example/a', 'alt': ''},
        ],
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'x', 'type': 'image', 'src': 'https://user@host/a', 'alt': ''},
        ],
      },
      {
        'version': 1,
        'blocks': [
          {
            'id': 'x',
            'type': 'image',
            'src': '/ok',
            'alt': '',
            'caption': null,
          },
        ],
      },
      {
        'version': 1,
        'blocks': [
          {
            'id': 'x',
            'type': 'paragraph',
            'text': 'x',
            'inlines': [
              {'text': 'wrong'},
            ],
          },
        ],
      },
      {
        'version': 1,
        'blocks': [
          {
            'id': 'x',
            'type': 'paragraph',
            'text': 'x',
            'inlines': [
              {'text': 'x', 'href': 'javascript:alert(1)'},
            ],
          },
        ],
      },
      {
        'version': 1,
        'blocks': [
          {
            'id': 'x',
            'type': 'paragraph',
            'text': 'x',
            'inlines': [
              {
                'text': 'x',
                'marks': ['bold', 'bold'],
              },
            ],
          },
        ],
      },
      {
        'version': 1,
        'blocks': [
          {
            'id': 'x',
            'type': 'paragraph',
            'text': 'x',
            'inlines': [
              {
                'text': 'x',
                'marks': ['future'],
              },
            ],
          },
        ],
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'x', 'type': 'paragraph', 'text': 'x'},
          {'id': 'x', 'type': 'paragraph', 'text': 'y'},
        ],
      },
    ];
    for (final item in invalid) {
      final model = BlogModel.fromNowaveArticle({
        'contentBlocksVersion': item['version'],
        'contentBlocks': item['blocks'],
      });
      expect(model.document?.supported, isFalse, reason: '$item');
      expect(model.plainEditorCompatible, isFalse, reason: '$item');
      expect(model.documentJson, isNotNull, reason: '$item');
      expect(
        decodeCachedArticleDocument(model.documentJson)?.supported,
        isFalse,
      );
    }
  });

  test('cache envelope handles old, corrupt and oversized rows safely', () {
    expect(decodeCachedArticleDocument(null), isNull);
    for (final invalid in ['{', 'null', '[]', '{}', 'x' * 1100001]) {
      expect(decodeCachedArticleDocument(invalid)?.supported, isFalse);
    }
    final article = structuredArticle();
    final encoded = encodeArticleDocument(
      version: article['contentBlocksVersion'],
      blocks: article['contentBlocks'],
    );
    expect(decodeCachedArticleDocument(encoded)?.blocks, hasLength(7));
  });
}
