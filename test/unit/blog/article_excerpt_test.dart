import 'package:belog/core/config/app_limits.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/reader/article_excerpt.dart';
import 'package:flutter_test/flutter_test.dart';

Blog _blog({
  String content = '',
  String summary = '',
  ArticleDocument? document,
}) => Blog(
  id: 'slug',
  title: 'Title',
  content: content,
  summary: summary,
  document: document,
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2026, 11, 19),
);

ArticleTextBlock _text(
  String id,
  String text, {
  ArticleTextKind kind = ArticleTextKind.paragraph,
}) => ArticleTextBlock(id: id, kind: kind, text: text, runs: const []);

ArticleDocument _document(List<ArticleBlock> blocks) =>
    ArticleDocument(version: 0, blocks: blocks);

/// The server's own cut of [text] at 110 characters, closed the way
/// `article-summary.ts` closes it: trailing punctuation stripped, then `…`.
String _serverCut(String text) {
  final runes = text.runes.take(110).toList();
  final cut = String.fromCharCodes(
    runes,
  ).replaceFirst(RegExp(r'[\p{P}\p{S}\s]+$', unicode: true), '');
  return '$cut\u2026';
}

void main() {
  const sentence = '夜里的城市像一张没有写完的稿纸，路灯一盏一盏亮起来，把街道切成整齐的段落。';
  final longBody = List.filled(10, sentence).join();

  group('excerptOf', () {
    test('a text that fits is returned whole, as the author ended it', () {
      expect(excerptOf('天亮了。雨还在下。'), '天亮了。雨还在下。');
      expect(excerptOf('  天亮了。\n\n 雨还在下。 '), '天亮了。 雨还在下。');
    });

    test('a cut keeps the first 150 characters and adds three dots', () {
      final excerpt = excerptOf(longBody);
      expect(excerpt, endsWith('...'));
      final body = excerpt.substring(0, excerpt.length - 3);
      expect(body.runes.length, lessThanOrEqualTo(150));
      expect(longBody.startsWith(body), isTrue);
    });

    test('a cut never ends on punctuation before the dots', () {
      // Put every kind of mark exactly on the cut.
      for (final mark in ['，', '。', '、', '：', '」', '”', '！', '？', ',', '.']) {
        final text = '${'字' * 149}$mark${'后' * 20}';
        expect(excerptOf(text), '${'字' * 149}...', reason: mark);
      }
      // A run of marks straddling the cut goes as a whole.
      final runOfMarks = '${'字' * 145}……——「」，。${'后' * 20}';
      expect(excerptOf(runOfMarks), '${'字' * 145}...');
    });

    test('the character before the dots is always a letter', () {
      final cut = excerptOf(longBody);
      final last = cut.substring(0, cut.length - 3).runes.last;
      expect(
        RegExp(
          r'[\p{L}\p{N}]',
          unicode: true,
        ).hasMatch(String.fromCharCode(last)),
        isTrue,
      );
    });

    test('a Latin word is never split in the middle', () {
      final text = List.filled(40, 'quietly').join(' ');
      final excerpt = excerptOf(text);
      expect(excerpt, endsWith('quietly...'));
      expect(excerpt.runes.length, lessThanOrEqualTo(153));
    });

    test('an emoji on the cut leaves no symbol or joiner behind', () {
      final text = '${'字' * 148}\u2764\uFE0F${'后' * 10}';
      expect(excerptOf(text), '${'字' * 148}...');
    });

    test('nothing but marks gives no excerpt', () {
      expect(excerptOf('。' * 200), '');
      expect(excerptOf(''), '');
    });

    test('the limit is the configured one', () {
      expect(AppLimits.articleExcerptCharacters, 150);
      expect(excerptOf('一二三四五六', limit: 3), '一二三...');
    });
  });

  group('articleExcerpt', () {
    test('an excerpt the author wrote is shown as written', () {
      final blog = _blog(
        summary: '一封迟到了二十年的信。',
        document: _document([_text('p', longBody)]),
      );
      expect(articleExcerpt(blog), '一封迟到了二十年的信。');
    });

    test('a long excerpt of the author is cut the same way', () {
      final blog = _blog(
        summary: '${'序' * 149}，${'后' * 30}',
        document: _document([_text('p', '正文。')]),
      );
      expect(articleExcerpt(blog), '${'序' * 149}...');
    });

    test('a server summary of the opening is replaced by a longer cut', () {
      final blog = _blog(
        summary: _serverCut(longBody),
        document: _document([_text('p', longBody)]),
      );
      final excerpt = articleExcerpt(blog);
      expect(excerpt, excerptOf(longBody));
      expect(excerpt, isNot(blog.summary));
    });

    test('a short whole-body server summary is recognised too', () {
      final blog = _blog(
        summary: '开篇雨下了一夜。',
        document: _document([
          _text('h', '开篇', kind: ArticleTextKind.heading),
          _text('p', '雨下了一夜。'),
        ]),
      );
      // The row keeps the heading apart from the paragraph after it.
      expect(articleExcerpt(blog), '开篇 雨下了一夜。');
    });

    test('without a summary the opening prose is used', () {
      final blog = _blog(
        document: _document([
          const ArticleImageBlock(id: 'i', src: 'https://cdn/x.jpg', alt: ''),
          const ArticleCodeBlock(id: 'c', language: 'dart', code: 'hidden();'),
          _text('p', '天亮了。'),
          const ArticleListBlock(
            id: 'l',
            ordered: false,
            items: [
              ArticleListItem(text: '甲', runs: []),
              ArticleListItem(text: '乙', runs: []),
            ],
          ),
          _text('q', 'Then the rain.', kind: ArticleTextKind.quote),
        ]),
      );
      expect(articleExcerpt(blog), '天亮了。甲，乙 Then the rain.');
    });

    test('a legacy Markdown body loses its markup', () {
      final blog = _blog(
        content:
            '# 标题\n\n'
            '> 引用的**一句**话\n\n'
            '```\ncode();\n```\n\n'
            '![图](https://cdn/a.png) 看 [这里](https://x.y) 的说明。',
      );
      expect(articleExcerpt(blog), '标题 引用的一句话 看 这里 的说明。');
    });

    test('an article with no prose has no excerpt', () {
      final blog = _blog(
        document: _document([
          const ArticleImageBlock(id: 'i', src: 'https://cdn/x.jpg', alt: ''),
        ]),
      );
      expect(articleExcerpt(blog), '');
    });
  });
}
