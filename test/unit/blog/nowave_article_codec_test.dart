import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plain editor compatibility', () {
    const paragraph = {'id': 'p', 'type': 'paragraph', 'text': '正文'};
    const cover = {
      'id': 'cover',
      'type': 'image',
      'src': 'https://api.example.invalid/cover',
      'alt': '',
    };

    test('accepts the v0 shapes created by the app', () {
      expect(supportsPlainEditor(version: 0, blocks: [paragraph]), isTrue);
      expect(
        supportsPlainEditor(version: 0, blocks: [cover, paragraph]),
        isTrue,
      );
    });

    test('rejects unknown versions and structured blocks', () {
      for (final version in [null, 1, 2, '0']) {
        expect(
          supportsPlainEditor(version: version, blocks: [paragraph]),
          isFalse,
        );
      }
      expect(
        supportsPlainEditor(
          version: 0,
          blocks: [
            {'id': 'h', 'type': 'heading', 'text': '标题', 'level': 2},
            paragraph,
          ],
        ),
        isFalse,
      );
      expect(
        supportsPlainEditor(version: 0, blocks: [cover, paragraph, cover]),
        isFalse,
      );
      expect(
        supportsPlainEditor(version: 0, blocks: [paragraph, cover]),
        isFalse,
      );
      expect(
        supportsPlainEditor(
          version: 0,
          blocks: [
            {...cover, 'alt': 'An illustration'},
            paragraph,
          ],
        ),
        isFalse,
      );
    });

    test('fails closed for hidden fields and lossy whitespace', () {
      expect(
        supportsPlainEditor(
          version: 0,
          blocks: [
            {...paragraph, 'inlines': []},
          ],
        ),
        isFalse,
      );
      expect(
        supportsPlainEditor(
          version: 0,
          blocks: [
            {...paragraph, 'text': 'first\n\nsecond'},
          ],
        ),
        isFalse,
      );
      expect(supportsPlainEditor(version: 0, blocks: []), isFalse);
    });

    test('fresh server models retain the decision across copies', () {
      final model = BlogModel.fromNowaveArticle({
        'slug': 'test',
        'id': 'id',
        'summary': '作者的摘要',
        'contentBlocksVersion': 0,
        'contentBlocks': [paragraph],
      });
      expect(model.plainEditorCompatible, isTrue);
      expect(model.serverSummary, '作者的摘要');
      expect(model.copyWith(title: 'changed').plainEditorCompatible, isTrue);
      expect(model.copyWith(title: 'changed').serverSummary, '作者的摘要');
      // A structured document the editor's Markdown can carry is editable...
      final structured = BlogModel.fromNowaveArticle({
        'slug': 'test',
        'id': 'id',
        'contentBlocksVersion': 1,
        'contentBlocks': [paragraph],
      });
      expect(structured.plainEditorCompatible, isTrue);
      expect(structured.editableBody?.markdown, '正文');
      // ...one it cannot carry (a quote attribution) stays closed.
      final richer = BlogModel.fromNowaveArticle({
        'slug': 'test',
        'id': 'id',
        'contentBlocksVersion': 1,
        'contentBlocks': [
          {'id': 'q', 'type': 'quote', 'text': '引文', 'attribution': '某人'},
        ],
      });
      expect(richer.plainEditorCompatible, isFalse);
      expect(richer.editableBody, isNull);
      expect(richer.copyWith(title: 'changed').plainEditorCompatible, isFalse);
    });
  });

  group('blogToContentBlocks', () {
    test('blank-line separated passages become paragraph blocks with ids', () {
      final blocks = blogToContentBlocks(content: '第一段\n\n第二段', coverUrl: null);

      expect(blocks, hasLength(2));
      expect(blocks.every((b) => (b['id'] as String).isNotEmpty), isTrue);
      expect(blocks[0]['type'], 'paragraph');
      expect(blocks[0]['text'], '第一段');
      expect(blocks[1]['text'], '第二段');
      expect(blocks.where((b) => b['type'] == 'image'), isEmpty);
    });

    test('the cover becomes the leading image block', () {
      final blocks = blogToContentBlocks(
        content: '正文',
        coverUrl: 'https://api.example.invalid/api/v1/media/x',
      );

      expect(blocks.first['type'], 'image');
      expect(blocks.first['src'], 'https://api.example.invalid/api/v1/media/x');
      expect(blocks.first['alt'], '');
      expect(blocks[1]['type'], 'paragraph');
    });

    test('internal single newlines stay inside one paragraph', () {
      final blocks = blogToContentBlocks(
        content: '行一\n行二\n\n第二段',
        coverUrl: null,
      );

      expect(blocks, hasLength(2));
      expect(blocks[0]['text'], '行一\n行二');
    });

    test('every block id is unique', () {
      final blocks = blogToContentBlocks(
        content: '一\n\n二\n\n三\n\n四',
        coverUrl: 'https://api.example.invalid/api/v1/media/x',
      );

      final ids = blocks.map((b) => b['id'] as String).toSet();
      expect(ids, hasLength(blocks.length));
    });

    test('whitespace-only bodies are rejected client-side', () {
      expect(
        () => blogToContentBlocks(content: '  \n\n  ', coverUrl: null),
        throwsA(isA<ServerException>()),
      );
    });

    test('oversized passages are split below the per-block limit', () {
      final longPassage = 'x' * 45000;
      final blocks = blogToContentBlocks(
        content: '$longPassage\n\n短段',
        coverUrl: null,
      );

      expect(blocks.last['text'], '短段');
      final textBlocks = blocks.sublist(0, blocks.length - 1);
      expect(textBlocks, isNotEmpty);
      for (final block in textBlocks) {
        expect((block['text'] as String).length, lessThanOrEqualTo(20000));
      }
      // No content is lost.
      final rejoined = textBlocks.map((b) => b['text'] as String).join();
      expect(rejoined.length, 45000);
    });
  });

  group('extractBlogContent', () {
    test('flattens paragraphs, lists, code and quote blocks to text', () {
      final extracted = extractBlogContent([
        {'id': 'a', 'type': 'paragraph', 'text': '第一段'},
        {'id': 'b', 'type': 'heading', 'text': '标题', 'level': 2},
        {'id': 'c', 'type': 'quote', 'text': '引文', 'attribution': '某人'},
        {
          'id': 'd',
          'type': 'list',
          'ordered': true,
          'items': ['一', '二'],
        },
        {'id': 'e', 'type': 'code', 'language': 'ts', 'code': 'const x = 1;'},
      ]);

      expect(extracted.content, '第一段\n\n标题\n\n引文\n\n一\n二\n\nconst x = 1;');
      expect(extracted.coverUrl, '');
    });

    test('the first image block becomes the cover, later ones degrade to '
        'captions', () {
      final extracted = extractBlogContent([
        {
          'id': 'a',
          'type': 'image',
          'src': 'https://api.example.invalid/api/v1/media/1',
          'alt': '',
        },
        {'id': 'b', 'type': 'paragraph', 'text': '正文'},
        {
          'id': 'c',
          'type': 'image',
          'src': 'https://api.example.invalid/api/v1/media/2',
          'alt': '',
          'caption': '插图说明',
        },
      ]);

      expect(extracted.coverUrl, 'https://api.example.invalid/api/v1/media/1');
      expect(extracted.content, '正文\n\n插图说明');
    });

    test('empty block lists extract to empty content', () {
      final extracted = extractBlogContent(const []);
      expect(extracted.content, '');
      expect(extracted.coverUrl, '');
    });
  });

  group('round trip', () {
    test('content survives a write-then-read cycle', () {
      const content = '第一段\n\n第二行\n第二段\n\n结尾';
      final blocks = blogToContentBlocks(
        content: content,
        coverUrl: 'https://api.example.invalid/api/v1/media/cover',
      );
      final extracted = extractBlogContent(blocks);

      expect(extracted.content, content);
      expect(
        extracted.coverUrl,
        'https://api.example.invalid/api/v1/media/cover',
      );
    });
  });

  group('articleBodyPayload', () {
    test('unformatted text keeps the version 0 shape', () {
      final payload = articleBodyPayload(
        content: '第一段\n\n第二段 5 * 3',
        coverUrl: 'https://api.example.invalid/api/v1/media/cover',
      );
      expect(payload.version, 0);
      expect(payload.blocks.map((block) => block['type']), [
        'image',
        'paragraph',
        'paragraph',
      ]);
      expect(payload.blocks[2]['text'], '第二段 5 * 3');
      expect(
        payload.blocks.every((block) => !block.containsKey('inlines')),
        isTrue,
      );
    });

    test('formatting is written as a version 1 document', () {
      final payload = articleBodyPayload(
        content:
            '## 小标题\n\n'
            '这是 **重点** 和 [链接](https://example.com)。\n\n'
            '- 一\n- 二\n\n'
            '> 引用\n\n'
            '```dart\nmain();\n```\n\n'
            '![图](https://example.com/p.png)',
        coverUrl: 'https://api.example.invalid/api/v1/media/cover',
      );
      expect(payload.version, 1);
      final blocks = payload.blocks;
      expect(blocks.map((block) => block['type']), [
        'image',
        'heading',
        'paragraph',
        'list',
        'quote',
        'code',
        'image',
      ]);
      // The cover leads with an empty description, as the app always wrote.
      expect(blocks[0]['alt'], '');
      expect(blocks[1]['level'], 2);
      expect(blocks[1]['text'], '小标题');
      expect(blocks[2]['text'], '这是 重点 和 链接。');
      final inlines = (blocks[2]['inlines'] as List)
          .cast<Map<String, dynamic>>();
      expect(inlines.map((run) => run['text']).join(), blocks[2]['text']);
      expect(inlines.firstWhere((run) => run['text'] == '重点')['marks'], [
        'bold',
      ]);
      expect(
        inlines.firstWhere((run) => run['text'] == '链接')['href'],
        'https://example.com',
      );
      expect(blocks[3]['ordered'], isFalse);
      expect(blocks[3]['items'], ['一', '二']);
      expect(blocks[3].containsKey('itemInlines'), isFalse);
      expect(blocks[5]['language'], 'dart');
      expect(blocks[5]['code'], 'main();');
      expect(blocks[6]['alt'], '图');
      final ids = blocks.map((block) => block['id'] as String).toSet();
      expect(ids, hasLength(blocks.length));
      expect(ids.every((id) => id.isNotEmpty && id.length <= 100), isTrue);
    });

    test('an empty body is still refused before any request', () {
      expect(
        () => articleBodyPayload(content: '  \n\n '),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
