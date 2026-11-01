import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_document.dart';
import 'package:belog/features/blog/presentation/read_aloud/structured_article_nodes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import '../../support/structured_article_fixtures.dart';

void main() {
  test('structured nodes preserve order, resources and literal code/text', () {
    final document = BlogModel.fromNowaveArticle(structuredArticle()).document!;
    final nodes = structuredArticleNodes(
      document,
      webBaseUrl: 'https://web.test/base',
    );
    expect(nodes.map((n) => (n as md.Element).tag), [
      'h2',
      'p',
      'p',
      'p',
      'blockquote',
      'ol',
      'p',
      'p',
      'pre',
    ]);
    final firstImage =
        ((nodes[1] as md.Element).children!.single as md.Element);
    final secondImage =
        ((nodes[6] as md.Element).children!.single as md.Element);
    expect(firstImage.attributes['src'], 'https://web.test/media/one.png');
    expect(firstImage.attributes['alt'], 'First image alt');
    expect(secondImage.attributes['src'], 'https://web.test/media/two.png');
    expect(nodes[2].textContent, 'First caption');
    expect(nodes[3].textContent, 'literal **asterisks**');
    expect(nodes[4].textContent, 'Quoted words— Author name');
    expect(nodes[5].textContent, 'First item second item ');
    final code = nodes.last as md.Element;
    expect(code.attributes['data-language'], 'dart');
    expect(markdownCodeText(code), '  a\n\n b  \n');

    final heading = nodes.first as md.Element;
    final link = heading.children!.first as md.Element;
    expect(link.tag, 'a');
    expect(link.attributes['href'], 'https://web.test/guide');
    final styled = link.children!.single as md.Element;
    expect(styled.attributes['data-bold'], 'true');
    expect(styled.attributes['data-italic'], 'true');
    expect(styled.attributes['data-underline'], 'true');
    expect(styled.attributes['data-strikethrough'], 'true');
    final codeLink = heading.children!.last as md.Element;
    expect((codeLink.children!.single as md.Element).tag, 'code');
  });

  test('unconfigured web base never guesses an origin', () {
    final document = BlogModel.fromNowaveArticle(structuredArticle()).document!;
    final nodes = structuredArticleNodes(document, webBaseUrl: '');
    final image = (nodes[1] as md.Element).children!.single as md.Element;
    expect(image.attributes['src'], isEmpty);
    final heading = nodes.first as md.Element;
    expect((heading.children!.first as md.Element).tag, 'span');
    expect((heading.children!.last as md.Element).tag, 'a'); // absolute link
  });

  test(
    'shared speech AST includes captions and attribution, not URLs or image alt',
    () {
      final document = BlogModel.fromNowaveArticle(
        structuredArticle(),
      ).document!;
      final nodes = structuredArticleNodes(
        document,
        webBaseUrl: 'https://web.test',
      );
      final speech = ReadAloudDocument.fromNodes('Sample title', nodes);
      expect(speech.blocks.map((b) => b.text), [
        'Sample title',
        'Bold代码',
        'First caption',
        'literal **asterisks**',
        'Quoted words',
        '— Author name',
        'First item',
        ' second item ',
        'Second caption',
        '  a\n\n b  \n',
      ]);
      expect(
        speech.blocks.map((b) => b.text).join(' '),
        isNot(contains('First image alt')),
      );
      expect(
        speech.blocks.map((b) => b.text).join(' '),
        isNot(contains('https://')),
      );
      final header = speech.blocks[1];
      expect(header.visualOffset(0), 0);
      expect(header.visualOffset(4), 4); // inline-code WidgetSpan starts here
      expect(header.visualOffset(5), 4);
      expect(
        header.inlineRanges.values.any((r) => r.start == 4 && r.end == 6),
        isTrue,
      );
      final code = speech.blocks.last;
      expect(code.inlineRanges[code.node]?.start, 0);
      expect(speech.chunks.last.text, 'b');
      expect(speech.chunks.last.blockOffset, 6);
    },
  );
}
