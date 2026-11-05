import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/features/blog/presentation/widgets/markdown_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpMarkdown(WidgetTester tester, String source) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(child: MarkdownBody(markdown: source)),
      ),
    ),
  );
}

void main() {
  testWidgets('plain text renders as paragraphs (legacy articles)', (
    tester,
  ) async {
    await pumpMarkdown(tester, '第一段。\n\n第二段。');

    expect(find.text('第一段。'), findsOneWidget);
    expect(find.text('第二段。'), findsOneWidget);
  });

  testWidgets('headings, lists, quotes and code blocks render', (tester) async {
    await pumpMarkdown(tester, '''
# 标题一

- 甲
- 乙

> 引用的话

```
print('hi');
```
''');

    expect(find.text('标题一'), findsOneWidget);
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('引用的话'), findsOneWidget);
    expect(find.text("print('hi');"), findsOneWidget);
  });

  testWidgets('tight list items keep inline formatting in one paragraph', (
    tester,
  ) async {
    await pumpMarkdown(
      tester,
      '- A **bold** [link](https://example.invalid)\n  - nested',
    );
    expect(find.text('A bold link'), findsOneWidget);
    expect(find.text('nested'), findsOneWidget);
  });

  testWidgets('bold and italic text is styled, not shown as asterisks', (
    tester,
  ) async {
    await pumpMarkdown(tester, '这是**加粗**和*斜体*');

    final rich = tester.widget<Text>(find.byType(Text).first);
    final span = rich.textSpan!;
    // The spans carry the styles; the raw asterisks never surface.
    expect(span.toPlainText(), contains('加粗'));
    expect(span.toPlainText(), isNot(contains('**')));
  });

  testWidgets('raw HTML is shown inertly, never executed', (tester) async {
    await pumpMarkdown(
      tester,
      '<script>alert(1)</script>\n\n<img src="x" onerror="alert(1)">',
    );

    // The parser escapes inline HTML into text: it is visible as
    // characters, and no widget interprets it.
    expect(find.textContaining('script'), findsWidgets);
  });

  testWidgets('javascript: links are inert (no tap recognizer)', (
    tester,
  ) async {
    await pumpMarkdown(tester, '[点我](javascript:alert(1))');

    expect(find.text('点我'), findsOneWidget);
    final rich = tester.widget<Text>(find.byType(Text).first);
    final paragraph = rich.textSpan! as TextSpan;
    // No recognizer on a non-http(s) target: the span cannot be tapped.
    expect(
      paragraph.children!.every(
        (span) => span is! TextSpan || span.recognizer == null,
      ),
      isTrue,
    );
  });

  testWidgets('an http(s) link gets a tap recognizer', (tester) async {
    await pumpMarkdown(tester, '[官网](https://example.invalid)');

    final rich = tester.widget<Text>(find.byType(Text).first);
    final paragraph = rich.textSpan! as TextSpan;
    expect(
      paragraph.children!.any(
        (span) => span is TextSpan && span.recognizer != null,
      ),
      isTrue,
    );
  });

  testWidgets('empty content renders nothing', (tester) async {
    await pumpMarkdown(tester, '');

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('garbage input degrades to text, not a crash', (tester) async {
    await pumpMarkdown(tester, '```\n未闭合的代码块');

    expect(find.textContaining('未闭合'), findsOneWidget);
  });

  testWidgets('renders in a light theme too (dark/light parity)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,

        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(markdown: '# 亮色主题\n\n正文'),
          ),
        ),
      ),
    );

    expect(find.text('亮色主题'), findsOneWidget);
  });

  testWidgets('a link around an inline code span is a real link (a11y)', (
    tester,
  ) async {
    // The code span becomes a WidgetSpan, so the paragraph's inline semantics
    // cannot describe it (#24). Before the fix this node was plain text with a
    // bare GestureDetector: TalkBack/VoiceOver announced no link and offered
    // no way to follow it.
    final handle = tester.ensureSemantics();
    await pumpMarkdown(tester, 'see [`belog`](https://example.invalid)');

    final links = _semanticsNodes(
      tester,
    ).where((node) => node.getSemanticsData().flagsCollection.isLink).toList();
    expect(
      links,
      hasLength(1),
      reason: 'the code link must keep its link role',
    );
    final data = links.single.getSemanticsData();
    expect(data.label, contains('belog'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('readers with 2x text still get the link semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(
              markdown: 'see [`belog`](https://example.invalid)',
            ),
          ),
        ),
      ),
    );

    final links = _semanticsNodes(
      tester,
    ).where((node) => node.getSemanticsData().flagsCollection.isLink).toList();
    expect(links, isNotEmpty);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}

/// Every semantics node below the rendered markdown body, so an assertion does
/// not depend on how deep the renderer nests the paragraph.
List<SemanticsNode> _semanticsNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(MarkdownBody)));
  return nodes;
}
