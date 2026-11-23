import 'dart:io';

import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/router/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'router_test.dart' show Harness, sampleUser;

/// The persona sweep: the checks the mobile-agent-testers phones run on
/// every screen they see, made deterministic and run on every push.
///
/// Each persona is a device from that project's personas.json, narrowed to
/// the two interface languages this app ships (a German or Swedish phone
/// falls back to one of them anyway). For every persona the real router
/// opens the main screens - the same first walk an agent takes - and each
/// screen is audited at the top and again scrolled to its end:
///
/// - nothing overflows or throws while laying out;
/// - every tappable control is at least 48 x 48 (the app's own tap target,
///   stricter than iOS's 44 pt);
/// - every tappable control has a name a screen reader can say;
/// - text meets the WCAG contrast minimum against what is painted under it.
///
/// A failure lists every finding of that screen, so one CI run reads like an
/// agent's report. Run with `--dart-define=PERSONA_SWEEP_REPORT=true` to
/// collect every finding without failing and print one compact report at
/// the end instead. See docs/agent-testers.md.
class Persona {
  const Persona({
    required this.id,
    required this.device,
    required this.size,
    required this.textScale,
    required this.themeMode,
    required this.locale,
    this.platform = TargetPlatform.android,
  });

  final String id;
  final String device;
  final Size size;
  final double textScale;
  final ThemeMode themeMode;
  final Locale locale;
  final TargetPlatform platform;

  @override
  String toString() =>
      '$id ($device, ${textScale}x, ${themeMode.name}, '
      '${locale.languageCode})';
}

/// Logical sizes are the devices' portrait viewports in dp / pt; text scales
/// are the platform steps the personas set (iOS accessibility sizes map to
/// Flutter's scaler through Dynamic Type's body size, 17 pt).
const personas = <Persona>[
  Persona(
    id: 'grace',
    device: 'Pixel 7, 200% font',
    size: Size(412, 915),
    textScale: 2,
    themeMode: ThemeMode.light,
    locale: Locale('en'),
  ),
  Persona(
    id: 'anna',
    device: 'Nexus 5, 130% font',
    size: Size(360, 640),
    textScale: 1.3,
    themeMode: ThemeMode.light,
    locale: Locale('en'),
  ),
  Persona(
    id: 'malik',
    device: 'Pixel 7, dark',
    size: Size(412, 915),
    textScale: 1,
    themeMode: ThemeMode.dark,
    locale: Locale('en'),
  ),
  Persona(
    id: 'lucia',
    device: 'Pixel Tablet, landscape',
    size: Size(1280, 800),
    textScale: 1,
    themeMode: ThemeMode.light,
    locale: Locale('en'),
  ),
  Persona(
    id: 'wei',
    device: 'iPhone 16e, extra large text',
    size: Size(390, 844),
    // Dynamic Type "xLarge": 21 / 17.
    textScale: 21 / 17,
    themeMode: ThemeMode.light,
    locale: Locale('zh'),
    platform: TargetPlatform.iOS,
  ),
  Persona(
    id: 'sven',
    device: 'iPhone SE, accessibility text, dark',
    size: Size(375, 667),
    // Dynamic Type "accessibility large" (AX2): 34 / 17. The personas'
    // largest step (AX5, ~3.1x) is past what the reading column is set
    // for; 2x on the smallest supported phone is the bar held here.
    textScale: 2,
    themeMode: ThemeMode.dark,
    locale: Locale('zh'),
    platform: TargetPlatform.iOS,
  ),
];

/// A screen of the first walk, opened at [location].
///
/// [arrange] changes what the fake backend answers before the app starts
/// (offline, a failing request); [act] is what the agent does once the
/// screen has settled (open a dialog, submit a form) before it is audited.
/// A screen with an [act] is audited where the act leaves it, without
/// scrolling: a dialog does not scroll the page under it.
class Screen {
  const Screen(
    this.name,
    this.location, {
    this.signedIn = false,
    this.arrange,
    this.act,
  });

  final String name;
  final String location;
  final bool signedIn;
  final void Function(Harness harness)? arrange;
  final Future<void> Function(WidgetTester tester, AppLocalizations l10n)? act;
}

final screens = <Screen>[
  const Screen('feed', RoutePaths.feed),
  Screen('article (guest)', RoutePaths.view(_slug)),
  const Screen('login', RoutePaths.login),
  const Screen('signup', RoutePaths.signup),
  const Screen('forgot password', RoutePaths.forgotPassword),
  const Screen('about', RoutePaths.about),
  Screen('article (signed in)', RoutePaths.view(_slug), signedIn: true),
  const Screen('profile', RoutePaths.profile, signedIn: true),
  const Screen('saved', RoutePaths.saved, signedIn: true),
  const Screen('my articles', RoutePaths.myArticles, signedIn: true),
  const Screen('search', RoutePaths.search),
  Screen('author page', RoutePaths.author('author')),
  const Screen('feed (offline)', RoutePaths.feed, arrange: _offline),
  Screen(
    'article (comments fail to load)',
    RoutePaths.view(_slug),
    arrange: _commentsFail,
  ),
  Screen(
    'article (delete-comment dialog)',
    RoutePaths.view(_slug),
    signedIn: true,
    act: _openDeleteDialog,
  ),
  const Screen('login (rejected)', RoutePaths.login, act: _rejectedLogin),
];

void _offline(Harness harness) {
  when(() => harness.connection.isConnected).thenAnswer((_) async => false);
}

void _commentsFail(Harness harness) {
  when(
    () => harness.commentRemote.getComments(any()),
  ).thenThrow(const SocketException('offline'));
}

Future<void> _openDeleteDialog(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  // The reader's own comment is the last one, at the end of the page.
  await _scrollToEnd(tester);
  final delete = find.widgetWithText(TextButton, l10n.actionDelete).first;
  await tester.ensureVisible(delete);
  await tester.pumpAndSettle();
  await tester.tap(delete);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _rejectedLogin(WidgetTester tester, AppLocalizations l10n) async {
  await tester.enterText(
    find.byType(TextFormField).first,
    'anna@example.invalid',
  );
  await tester.enterText(find.byType(TextFormField).last, 'wrong password');
  final submit = find.widgetWithText(NoWaveButton, l10n.loginTitle);
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

const _slug = 'night-city';

const _paragraph =
    'The city at night is a page nobody finished. Street lamps come on one '
    'by one and cut the road into tidy paragraphs.';

BlogModel _article(String id, String title, {String summary = ''}) => BlogModel(
  id: id,
  title: title,
  content: [for (var i = 0; i < 6; i++) _paragraph].join('\n\n'),
  summary: summary,
  posterId: 'author',
  posterName: 'Lin Yu',
  imageUrl: '',
  tags: const ['essay', 'city'],
  updatedAt: DateTime.utc(2025, 6, 1),
);

CommentModel _comment(
  String id,
  String content, {
  String authorId = 'reader',
  String authorName = 'A reader with a fairly long display name',
  String? parentId,
  List<CommentModel> replies = const [],
}) => CommentModel(
  id: id,
  articleId: 'server-article',
  authorId: authorId,
  authorName: authorName,
  parentCommentId: parentId,
  content: content,
  createdAt: DateTime.utc(2025, 6, 2),
  replies: replies,
);

void _stub(Harness harness) {
  final feed = [
    _article(
      _slug,
      'An unfinished page: notes on the city at night',
      summary: 'Street lamps cut the road into tidy paragraphs.',
    ),
    _article('second', '夜里的城市是一页没人写完的稿纸'),
    _article('third', 'A short one'),
  ];
  when(() => harness.remote.getAllBlogs(page: 1)).thenAnswer((_) async => feed);
  when(
    () => harness.remote.getBlogById(any()),
  ).thenAnswer((_) async => feed.first);
  when(
    () => harness.remote.getRelatedArticles(any()),
  ).thenAnswer((_) async => feed.skip(1).toList());
  when(
    () => harness.remote.getUserLikedBlogs(any()),
  ).thenAnswer((_) async => feed.take(2).toList());
  when(
    () => harness.remote.isBlogLikedByUser(any(), any()),
  ).thenAnswer((_) async => false);
  when(
    () => harness.authRepository.loginWithEmailPassword(
      email: any(named: 'email'),
      password: any(named: 'password'),
      intent: any(named: 'intent'),
    ),
  ).thenAnswer((_) async => left<Failure, User>(Failure.auth('rejected')));
  when(() => harness.commentRemote.getComments(any())).thenAnswer(
    (_) async => CommentPage(
      items: [
        _comment(
          'c1',
          'The paragraph about the lamps stayed with me all evening.',
          replies: [
            _comment(
              'c2',
              'Thank you - it started as a walk home.',
              authorId: 'author',
              authorName: 'Lin Yu',
              parentId: 'c1',
            ),
          ],
        ),
        _comment(
          'c3',
          'My own note, so I can edit or delete it.',
          authorId: sampleUser().id,
          authorName: sampleUser().name,
        ),
      ],
      nextCursor: null,
    ),
  );
}

/// Report mode: collect, never fail, print once at the end.
const _reportOnly = bool.fromEnvironment('PERSONA_SWEEP_REPORT');

/// "screen | finding" -> the personas that hit it, in sweep order.
final _report = <String, List<String>>{};

/// One finding on one line: the node ids, rectangles, tags and links of a
/// guideline's reason say nothing a reader of the report can act on.
String _compact(String text) => text
    .replaceAll(RegExp(r'SemanticsNode#\d+\(Rect\.fromLTRB\([^)]*\),?'), '')
    .replaceAll(RegExp(r'tags: \[[^\]]*\],?'), '')
    .replaceAll(RegExp(r'actions: \[[^\]]*\],?'), '')
    .replaceAll(RegExp(r'flags: \[[^\]]*\],?'), '')
    .replaceAll(RegExp(r'textDirection: \w+\)?'), '')
    .replaceAll(RegExp(r'See also: \S+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Chinese the fixtures put on screen as content (titles, names, tags) and
/// the two Chinese strings the English interface carries on purpose: the
/// language's own name in the language menu and the brand's subline.
final _contentInChinese = <String>{
  '\u591c\u91cc\u7684\u57ce\u5e02', // the second article's title
  sampleUser().name,
  '\u6df1\u94fe', // the harness's default author and article
  '\u8bd7\u6b4c', // the harness's default tag
  '\u4e2d\u6587', // languageChinese
  '\u7121\u6d6a\u6f6e', // splashBrandSubline
};

final _han = RegExp(r'[\u4e00-\u9fff]');

/// Short text that was cut, and Chinese left in the English interface: the
/// two kinds of copy bugs the agents report most after layout.
List<String> _copyFindings(Locale locale) {
  final findings = <String>{};
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText().trim();
    if (text.isEmpty) continue;
    // Titles and excerpts are clamped on purpose; a label, a button or a
    // name that loses its end is not.
    if (paragraph.didExceedMaxLines && text.runes.length <= 40) {
      findings.add('cut text | "$text"');
    }
    if (locale.languageCode == 'en' &&
        _han.hasMatch(text) &&
        !_contentInChinese.any(text.contains)) {
      findings.add('untranslated | "$text"');
    }
  }
  return findings.toList();
}

/// Everything wrong with what is on screen now.
Future<List<String>> _audit(WidgetTester tester, Locale locale) async {
  final findings = <String>[..._copyFindings(locale)];
  final error = tester.takeException();
  if (error != null) findings.add('layout/exception: $error');
  for (final guideline in <AccessibilityGuideline>[
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ]) {
    final result = await guideline.evaluate(tester);
    if (!result.passed) {
      final lines = (result.reason ?? '')
          .split('\n')
          .map(_compact)
          .where((line) => line.isNotEmpty);
      findings.addAll([
        for (final line in lines) '${guideline.description} | $line',
      ]);
    }
  }
  return findings;
}

/// Scrolls the page's longest vertical list to its end, the way an agent
/// swipes down a screen before leaving it. False when nothing scrolls.
Future<bool> _scrollToEnd(WidgetTester tester) async {
  ScrollPosition? longest;
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    final position = state.position;
    if (position.axis != Axis.vertical || !position.hasContentDimensions) {
      continue;
    }
    if (longest == null || position.maxScrollExtent > longest.maxScrollExtent) {
      longest = position;
    }
  }
  if (longest == null || longest.maxScrollExtent <= 0) return false;
  longest.jumpTo(longest.maxScrollExtent);
  await tester.pumpAndSettle();
  return true;
}

void main() {
  setUp(() => GetIt.instance.reset());
  if (_reportOnly) {
    tearDownAll(() {
      final lines = [
        for (final MapEntry(:key, :value) in _report.entries)
          '$key  <- ${value.join(',')}',
      ];
      // ignore: avoid_print
      print(
        '===== persona sweep report (${lines.length} findings) =====\n'
        '${lines.join('\n')}\n'
        '===== end of persona sweep report =====',
      );
    });
  }

  for (final persona in personas) {
    group(persona.toString(), () {
      for (final screen in screens) {
        testWidgets(screen.name, (tester) async {
          tester.view.physicalSize = persona.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();

          final harness = Harness();
          addTearDown(harness.dispose);
          _stub(harness);
          screen.arrange?.call(harness);
          if (screen.signedIn) harness.appUserCubit.updateUser(sampleUser());
          harness.buildRouter(initialLocation: screen.location);
          await harness.pump(
            tester,
            locale: persona.locale,
            textScale: persona.textScale,
            themeMode: persona.themeMode,
          );
          await tester.pumpAndSettle();
          final act = screen.act;
          if (act != null) {
            await act(tester, lookupAppLocalizations(persona.locale));
          }

          final findings = [
            for (final finding in await _audit(tester, persona.locale))
              '[top] $finding',
          ];
          if (act == null && await _scrollToEnd(tester)) {
            findings.addAll([
              for (final finding in await _audit(tester, persona.locale))
                '[end] $finding',
            ]);
          }
          semantics.dispose();
          if (_reportOnly) {
            for (final finding in findings) {
              _report
                  .putIfAbsent('${screen.name} | $finding', () => [])
                  .add(persona.id);
            }
            return;
          }
          expect(
            findings,
            isEmpty,
            reason:
                '$persona on ${screen.name}:\n'
                '${findings.join('\n')}',
          );
        }, variant: TargetPlatformVariant.only(persona.platform));
      }
    });
  }
}
