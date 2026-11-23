import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/data/models/comment_model.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/router/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
/// agent's report. See docs/agent-testers.md.
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
class Screen {
  const Screen(this.name, this.location, {this.signedIn = false});

  final String name;
  final String location;
  final bool signedIn;
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
];

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

/// Everything wrong with what is on screen now.
Future<List<String>> _audit(WidgetTester tester) async {
  final findings = <String>[];
  final error = tester.takeException();
  if (error != null) findings.add('layout/exception: $error');
  for (final guideline in <AccessibilityGuideline>[
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ]) {
    final result = await guideline.evaluate(tester);
    if (!result.passed) {
      findings.add('${guideline.description}:\n${result.reason}');
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

  for (final persona in personas) {
    group(persona.toString(), () {
      for (final screen in screens) {
        testWidgets(screen.name, (tester) async {
          tester.view.physicalSize = persona.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          addTearDown(semantics.dispose);

          final harness = Harness();
          addTearDown(harness.dispose);
          _stub(harness);
          if (screen.signedIn) harness.appUserCubit.updateUser(sampleUser());
          harness.buildRouter(initialLocation: screen.location);
          await harness.pump(
            tester,
            locale: persona.locale,
            textScale: persona.textScale,
            themeMode: persona.themeMode,
          );
          await tester.pumpAndSettle();

          final findings = [
            for (final finding in await _audit(tester)) '[top] $finding',
          ];
          if (await _scrollToEnd(tester)) {
            findings.addAll([
              for (final finding in await _audit(tester)) '[end] $finding',
            ]);
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
