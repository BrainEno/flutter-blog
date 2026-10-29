import 'package:belog/core/error/exceptions.dart';
import 'package:belog/features/blog/data/datasources/nowave_article_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
