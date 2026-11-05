import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/presentation/comments/comment_login_prompt.dart';
import 'package:belog/features/blog/presentation/widgets/article_reader_header.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/source_files.dart';

/// System text scaling is an accessibility setting, not a preference the app
/// may overrule (#24). These tests pin the two ends that matter: the largest
/// text scale the platforms offer (2.0) at a narrow 320 dp width, in both
/// interface languages.
///
/// A regression here is an overflow banner ("BOTTOM OVERFLOWED BY …") or a
/// clipped control, so each case asserts `takeException()` is null as well as
/// the visible content.
void main() {
  for (final locale in const [Locale('zh'), Locale('en')]) {
    group('${locale.languageCode} at 2x text', () {
      testWidgets('the reader header keeps its title, author and cover', (
        tester,
      ) async {
        await _pumpNarrow(tester, locale: locale, child: _header());

        expect(find.text(_title), findsOneWidget);
        expect(find.text(_author), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the empty/error status stays readable and announced', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final l10n = lookupAppLocalizations(locale);
        await _pumpNarrow(
          tester,
          locale: locale,
          child: NoWaveStatus(
            message: l10n.commentsEmpty,
            actionLabel: l10n.actionRetry,
            onAction: () {},
          ),
        );

        expect(find.text(l10n.commentsEmpty), findsOneWidget);
        expect(find.text(l10n.actionRetry), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byType(NoWaveStatus))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
          reason: '状态变化要被读屏播报',
        );
        expect(tester.takeException(), isNull);
        handle.dispose();
      });

      testWidgets('the signed-out comment prompt keeps its sign-in button', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(locale);
        await _pumpNarrow(
          tester,
          locale: locale,
          child: CommentLoginPrompt(onRequestLogin: () {}),
        );

        expect(find.text(l10n.loginToComment), findsOneWidget);
        expect(find.text(l10n.goSignIn), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('no source file clamps the system text scale', () {
    // `TextScaler.noScaling` / a fixed `textScaleFactor` would ignore the
    // reader's accessibility setting. Layouts adapt by measuring the scaler
    // (see `editor_field.dart`), never by resetting it.
    final offenders = <String>[];
    final banned = RegExp(
      r'TextScaler\.noScaling|textScaleFactor\s*:'
      r'|TextScaler\.linear\(\s*1(\.0)?\s*\)',
    );
    for (final file in dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (banned.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the app must honour the system text scale (#24); adapt the layout '
          'instead of clamping:\n${offenders.join('\n')}',
    );
  });
}

const _title = 'A title that has to wrap at 2x';
const _author = 'Writer';

Widget _header() {
  final blog = Blog(
    id: 'sample',
    title: _title,
    // Long enough to be a multi-minute read, so the reading-time label is a
    // translated phrase rather than a bare number.
    content: List.filled(2400, 'word').join(' '),
    posterId: 'author-1',
    imageUrl: '',
    tags: const ['诗歌'],
    updatedAt: DateTime.utc(2026, 10, 30),
    posterName: _author,
  );
  return SingleChildScrollView(
    child: ArticleReaderHeader(blog: blog, onAuthorTap: () {}),
  );
}

Future<void> _pumpNarrow(
  WidgetTester tester, {
  required Locale locale,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: appChild!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}
