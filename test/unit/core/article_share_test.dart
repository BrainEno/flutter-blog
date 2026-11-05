import 'package:belog/core/utils/article_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('articleWebUrl', () {
    test('builds the canonical web URL from the configured origin', () {
      expect(
        articleWebUrl('my-slug', webBaseUrl: 'https://bot-thk.example'),
        'https://bot-thk.example/articles/my-slug',
      );
    });

    test('trailing slashes on the origin are normalized', () {
      expect(
        articleWebUrl('my-slug', webBaseUrl: 'https://bot-thk.example/'),
        'https://bot-thk.example/articles/my-slug',
      );
    });

    test('no origin configured means no share URL (never a guessed link)', () {
      expect(articleWebUrl('my-slug', webBaseUrl: null), isNull);
      expect(articleWebUrl('my-slug', webBaseUrl: '  '), isNull);
    });

    test('an empty slug has no public page', () {
      expect(articleWebUrl('', webBaseUrl: 'https://bot-thk.example'), isNull);
    });

    test('without the dart-define the default is null in tests', () {
      // WEB_BASE_URL is not set in the test runner; the share entry must
      // hide rather than share something unopenable.
      expect(articleWebUrl('my-slug'), isNull);
    });
  });

  group('shareArticleText', () {
    test('carries the title, the excerpt and the link on its own line', () {
      expect(
        shareArticleText(
          title: '标题',
          url: 'https://bot-thk.example/articles/my-slug',
          summary: '一句话摘要',
        ),
        '标题\n\n一句话摘要\n\nhttps://bot-thk.example/articles/my-slug',
      );
    });

    test('an empty excerpt does not leave a blank block', () {
      expect(
        shareArticleText(
          title: '标题',
          url: 'https://bot-thk.example/articles/my-slug',
          summary: '   ',
        ),
        '标题\n\nhttps://bot-thk.example/articles/my-slug',
      );
    });
  });

  group('shareSummary', () {
    test('unwraps the light Markdown a blurb needs', () {
      expect(
        shareSummary('# 标题\n\n**正文** 第一段 [链接](https://example.invalid)'),
        '标题',
        reason: '取第一条有内容的行，不拼多行',
      );
      expect(
        shareSummary('\n\n> 引用**重点** [网站](https://example.invalid)'),
        '引用重点 网站',
      );
      expect(shareSummary('- 列表项一\n- 列表项二'), '列表项一');
    });

    test('fenced code is not prose', () {
      expect(shareSummary('```\nfinal x = 1;\n```'), isEmpty);
      expect(shareSummary('```\ncode\n```\n\n真正的摘要'), '真正的摘要');
    });

    test('rules and blank bodies produce nothing', () {
      expect(shareSummary('---\n___'), isEmpty);
      expect(shareSummary(''), isEmpty);
    });

    test('long lines are cut on a character boundary', () {
      final summary = shareSummary('一二三四五六七八九十', maxChars: 4);
      expect(summary, '一二三四…');
      // Emoji are surrogate pairs: cutting must not split one.
      expect(shareSummary('😀😀😀😀😀', maxChars: 2), '😀😀…');
    });
  });
}
