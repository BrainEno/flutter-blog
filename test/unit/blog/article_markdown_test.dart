import 'package:belog/features/blog/domain/authoring/article_markdown.dart';
import 'package:belog/features/blog/domain/entities/article_document.dart';
import 'package:flutter_test/flutter_test.dart';

ArticleTextBlock _text(
  ArticleTextKind kind,
  List<ArticleInlineRun> runs, {
  int? level,
  String? attribution,
}) => ArticleTextBlock(
  id: 'b-${runs.map((run) => run.text).join()}',
  kind: kind,
  text: runs.map((run) => run.text).join(),
  runs: runs,
  level: level,
  attribution: attribution,
);

ArticleInlineRun _run(String text, [Set<ArticleInlineMark> marks = const {}]) =>
    ArticleInlineRun(text: text, marks: marks);

void main() {
  group('parseArticleMarkdown', () {
    test('maps the editor dialect onto no-wave blocks', () {
      final blocks = parseArticleMarkdown(
        '# Top\n\n'
        '### Sub\n\n'
        'Plain *it* and **bold**.\n\n'
        '> quoted\n\n'
        '- a\n- b\n\n'
        '1. x\n2. y\n\n'
        '```dart\nvoid main() {}\n```\n\n'
        '![alt](https://example.com/a.png "cap")',
      );
      expect(blocks, hasLength(8));

      final top = blocks[0] as ArticleTextBlock;
      expect(top.kind, ArticleTextKind.heading);
      // The title field is the level 1; a single `#` is the first level kept.
      expect(top.level, 2);
      expect(top.text, 'Top');
      expect((blocks[1] as ArticleTextBlock).level, 3);

      final paragraph = blocks[2] as ArticleTextBlock;
      expect(paragraph.kind, ArticleTextKind.paragraph);
      expect(paragraph.text, 'Plain it and bold.');
      expect(paragraph.runs.firstWhere((run) => run.text == 'it').marks, {
        ArticleInlineMark.italic,
      });
      expect(paragraph.runs.firstWhere((run) => run.text == 'bold').marks, {
        ArticleInlineMark.bold,
      });

      final quote = blocks[3] as ArticleTextBlock;
      expect(quote.kind, ArticleTextKind.quote);
      expect(quote.text, 'quoted');

      final bullets = blocks[4] as ArticleListBlock;
      expect(bullets.ordered, isFalse);
      expect(bullets.items.map((item) => item.text), ['a', 'b']);
      final numbers = blocks[5] as ArticleListBlock;
      expect(numbers.ordered, isTrue);
      expect(numbers.items.map((item) => item.text), ['x', 'y']);

      final code = blocks[6] as ArticleCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'void main() {}');

      final image = blocks[7] as ArticleImageBlock;
      expect(image.src, 'https://example.com/a.png');
      expect(image.alt, 'alt');
      expect(image.caption, 'cap');
    });

    test('a fence without a language gets the web editor default', () {
      final code = parseArticleMarkdown('```\nx\n```').single;
      expect((code as ArticleCodeBlock).language, articleDefaultCodeLanguage);
    });

    test('only "1." interrupts a paragraph, so a year stays text', () {
      final blocks = parseArticleMarkdown('In the end\n2024. That year');
      expect(blocks, hasLength(1));
      expect((blocks.single as ArticleTextBlock).text, contains('2024.'));
    });

    test('numbered items keep one list across blank lines', () {
      final list = parseArticleMarkdown('1. one\n\n2. two\n\n3. three').single;
      expect((list as ArticleListBlock).items, hasLength(3));
    });

    test('plain text is plain paragraphs', () {
      final blocks = parseArticleMarkdown('First line\n\nSecond, 5 * 3 = 15');
      expect(isPlainParagraphs(blocks), isTrue);
      expect(blocks.map((block) => (block as ArticleTextBlock).text), [
        'First line',
        'Second, 5 * 3 = 15',
      ]);
    });
  });

  group('parseInlineRuns', () {
    test('underscores inside a word stay literal', () {
      final runs = parseInlineRuns('snake_case_name');
      expect(runs.single.text, 'snake_case_name');
      expect(runs.single.marks, isEmpty);
    });

    test('an unsafe link address stays literal text', () {
      final runs = parseInlineRuns('[x](javascript:alert)');
      expect(runs.map((run) => run.text).join(), '[x](javascript:alert)');
      expect(runs.every((run) => run.href == null), isTrue);
    });

    test('a safe link carries its address', () {
      final runs = parseInlineRuns('see [docs](https://example.com/d)');
      final link = runs.firstWhere((run) => run.href != null);
      expect(link.text, 'docs');
      expect(link.href, 'https://example.com/d');
    });

    test('escapes, inline code and underline', () {
      final runs = parseInlineRuns(r'\*not\* `a*b` <u>under</u>');
      expect(runs.map((run) => run.text).join(), '*not* a*b under');
      expect(runs.firstWhere((run) => run.text == 'a*b').marks, {
        ArticleInlineMark.code,
      });
      expect(runs.firstWhere((run) => run.text == 'under').marks, {
        ArticleInlineMark.underline,
      });
    });
  });

  group('editableBodyOf', () {
    test('renders a structured article and proves it reads back the same', () {
      final document = ArticleDocument(
        version: 1,
        blocks: [
          const ArticleImageBlock(
            id: 'cover',
            src: 'https://example.com/cover.png',
            alt: '',
          ),
          _text(ArticleTextKind.heading, [_run('Intro')], level: 3),
          _text(ArticleTextKind.paragraph, [
            _run('Say '),
            _run('loud', {ArticleInlineMark.bold}),
            _run(' and '),
            _run('*literal*'),
          ]),
          ArticleListBlock(
            id: 'l',
            ordered: true,
            items: [
              ArticleListItem(text: 'one', runs: [_run('one')]),
              ArticleListItem(text: 'two', runs: [_run('two')]),
            ],
          ),
          const ArticleCodeBlock(id: 'c', language: 'js', code: 'a();'),
          const ArticleImageBlock(
            id: 'i',
            src: 'https://example.com/in-body.png',
            alt: 'a chart',
          ),
        ],
      );
      final body = editableBodyOf(document);
      expect(body, isNotNull);
      expect(body!.coverUrl, 'https://example.com/cover.png');
      expect(
        body.markdown,
        '### Intro\n\n'
        'Say **loud** and \\*literal\\*\n\n'
        '1. one\n2. two\n\n'
        '```js\na();\n```\n\n'
        '![a chart](https://example.com/in-body.png)',
      );
      expect(
        sameArticleBlocks(
          document.blocks.sublist(1),
          parseArticleMarkdown(body.markdown),
        ),
        isTrue,
      );
    });

    test('an article without a leading cover has an empty cover', () {
      final body = editableBodyOf(
        ArticleDocument(
          version: 1,
          blocks: [
            _text(ArticleTextKind.paragraph, [_run('just text')]),
          ],
        ),
      );
      expect(body?.coverUrl, '');
      expect(body?.markdown, 'just text');
    });

    test('a quote attribution cannot be carried, so it fails closed', () {
      final body = editableBodyOf(
        ArticleDocument(
          version: 1,
          blocks: [
            _text(ArticleTextKind.quote, [_run('words')], attribution: 'Ada'),
          ],
        ),
      );
      expect(body, isNull);
    });

    test('an unknown document is never editable', () {
      expect(editableBodyOf(const ArticleDocument.unsupported(9)), isNull);
    });
  });

  group('renderInlineRuns', () {
    test('edge spaces stay outside emphasis', () {
      expect(
        renderInlineRuns([
          _run('a'),
          _run(' bold ', {ArticleInlineMark.bold}),
          _run('b'),
        ]),
        'a **bold** b',
      );
    });

    test('a code span grows its fence past the backticks inside', () {
      expect(
        renderInlineRuns([
          _run('x`y', {ArticleInlineMark.code}),
        ]),
        '``x`y``',
      );
    });
  });
}
