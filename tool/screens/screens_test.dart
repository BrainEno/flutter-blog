// Temporary: renders a few real screens to PNG so the UI can be reviewed
// without a device. Run by .github/workflows/screens.yml, never by `flutter
// test` (it lives outside test/). Delete together with that workflow.
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../../test/support/locale_test_support.dart';
import '../../test/support/read_aloud_fakes.dart';
import '../../test/widget/read_aloud_navigation_test.dart' show installSpeech;
import '../../test/widget/router_test.dart' show Harness, sampleUser;

const _fonts = 'build/screens_fonts';

late FakeSpeechEngine _engine;

Future<void> _family(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

const _paragraph =
    '夜里的城市像一张没有写完的稿纸。路灯一盏一盏亮起来，把街道切成整齐的段落，'
    '而我们只是其中被反复修改的句子。她说，写作不是为了被理解，是为了在某个'
    '深夜确认自己还在。窗外有人骑车经过，铃声很轻，像一个迟到的逗号。';

BlogModel _blog(int i, String title, {String? content}) => BlogModel(
  id: 'a$i',
  title: title,
  content: content ?? '$_paragraph\n\n$_paragraph',
  posterId: 'author',
  posterName: ['林间', '周默', 'Ada Lin', '许多'][i % 4],
  imageUrl: '',
  tags: const ['散文', '城市'],
  updatedAt: DateTime.utc(2026, 11, 18 - i),
  serverSummary: _paragraph.substring(0, 60),
);

final _titles = [
  '没有写完的稿纸',
  '在雨季结束之前',
  'Notes on a Quiet Machine',
  '一座城市的十二种读法',
  '母亲的厨房与南方的风',
];

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(seconds: 2));
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('out/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    await _family('InstrumentSerif', [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ]);
    // A phone falls back to its system CJK sans for InterTight; the test
    // engine has no system fonts, so the CJK sans stands in for both.
    await _family('InterTight', ['$_fonts/NotoSansSC.otf']);
    await _family('FlutterTest', ['$_fonts/NotoSansSC.otf']);
    await _family('Noto Serif CJK SC', ['$_fonts/NotoSerifSC.otf']);
    await _family('Noto Sans CJK SC', ['$_fonts/NotoSansSC.otf']);
    await _family('Roboto', ['$_fonts/NotoSansSC.otf']);
    await _family('MaterialIcons', ['$_fonts/MaterialIcons-Regular.otf']);
  });

  setUp(() => GetIt.instance.reset());

  Future<Harness> boot(
    WidgetTester tester,
    String location, {
    bool dark = false,
    void Function(Harness harness)? before,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
    addTearDown(tester.view.reset);
    final harness = Harness()..buildRouter(initialLocation: location);
    when(() => harness.remote.getAllBlogs(page: 1)).thenAnswer(
      (_) async => [for (final (i, t) in _titles.indexed) _blog(i, t)],
    );
    when(() => harness.remote.getBlogById(any())).thenAnswer(
      (_) async => _blog(
        0,
        _titles[0],
        content: [for (var i = 0; i < 8; i++) _paragraph].join('\n\n'),
      ),
    );
    before?.call(harness);
    final engine = FakeSpeechEngine();
    _engine = engine;
    installSpeech(engine);
    addTearDown(() async {
      await harness.dispose();
      await engine.close();
    });
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>.value(value: harness.themeBloc),
          BlocProvider<AuthBloc>.value(value: harness.authBloc),
          BlocProvider<AppUserCubit>.value(value: harness.appUserCubit),
          BlocProvider<LocaleBloc>(create: (_) => systemLocaleBloc()),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          theme: AppTheme.lightThemeMode,
          darkTheme: AppTheme.darkThemeMode,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: harness.router!.router,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    return harness;
  }

  testWidgets('home', (tester) async {
    await boot(tester, '/');
    await _shot(tester, '01-home');
  });

  testWidgets('home scrolled', (tester) async {
    await boot(tester, '/');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await _shot(tester, '02-home-scrolled');
  });

  testWidgets('article', (tester) async {
    await boot(tester, '/view/a0');
    await _shot(tester, '03-article');
  });

  testWidgets('article reading aloud, scrolled away', (tester) async {
    await boot(tester, '/view/a0');
    final play = find.byKey(const ValueKey('read-aloud-play'));
    await tester.ensureVisible(play);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(play);
    await tester.pump(const Duration(seconds: 1));
    // Title, then into the body, then a word a few lines down.
    _engine.event(_engine.calls.last.id, SpeechEventType.completed);
    await tester.pump(const Duration(seconds: 1));
    _engine.event(
      _engine.calls.last.id,
      SpeechEventType.range,
      start: 40,
      end: 42,
    );
    await tester.pump(const Duration(seconds: 1));
    // The reader drags away to look at something else.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -1400),
    );
    await tester.pump(const Duration(seconds: 1));
    _engine.event(
      _engine.calls.last.id,
      SpeechEventType.range,
      start: 50,
      end: 52,
    );
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '04-article-reading');
    // Up to the top to reach the full controls: the page must stay there.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 3000),
    );
    await tester.pump(const Duration(seconds: 1));
    _engine.event(
      _engine.calls.last.id,
      SpeechEventType.range,
      start: 60,
      end: 62,
    );
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '04b-article-reading-top');
  });

  Future<void> toEnd(WidgetTester tester, Harness harness) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -6000),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  void serveEnd(Harness harness) {
    when(() => harness.remote.getRelatedArticles(any())).thenAnswer(
      (_) async => [
        for (final (i, t) in _titles.indexed.skip(1)) _blog(i, t),
      ].take(3).toList(),
    );
    final now = DateTime.utc(2026, 11, 18, 9);
    when(() => harness.commentRemote.getComments(any())).thenAnswer(
      (_) async => CommentPage(
        items: [
          Comment(
            id: 'c1',
            articleId: 'a0',
            authorId: 'u2',
            authorName: '周默',
            content: '“像一个迟到的逗号”这一句读了好几遍。夜里的城市确实是这样的。',
            createdAt: now,
            replies: [
              Comment(
                id: 'c2',
                articleId: 'a0',
                authorId: 'author',
                authorName: '林间',
                parentCommentId: 'c1',
                content: '谢谢你读到这里。',
                createdAt: now.add(const Duration(hours: 2)),
              ),
            ],
          ),
          Comment(
            id: 'c3',
            articleId: 'a0',
            authorId: 'u3',
            authorName: 'Ada Lin',
            content: '写作不是为了被理解，是为了确认自己还在。',
            createdAt: now.add(const Duration(hours: 5)),
          ),
        ],
        nextCursor: 'next',
      ),
    );
  }

  testWidgets('article end, signed in', (tester) async {
    final harness = await boot(tester, '/view/a0', before: serveEnd);
    harness.appUserCubit.updateUser(sampleUser());
    await toEnd(tester, harness);
    await _shot(tester, '09-article-end');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 450),
    );
    await tester.pump(const Duration(seconds: 2));
    await _shot(tester, '09a-article-comments-head');
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 600),
    );
    await tester.pump(const Duration(seconds: 2));
    await _shot(tester, '09b-article-related');
  });

  testWidgets('article end, guest', (tester) async {
    final harness = await boot(tester, '/view/a0', before: serveEnd);
    await toEnd(tester, harness);
    await _shot(tester, '10-article-end-guest');
  });

  void serveSaved(Harness harness) {
    harness.appUserCubit.updateUser(sampleUser());
    when(() => harness.remote.getUserLikedBlogs(any())).thenAnswer(
      (_) async => [for (final (i, t) in _titles.indexed) _blog(i, t)],
    );
  }

  testWidgets('saved', (tester) async {
    await boot(tester, '/saved', before: serveSaved);
    await _shot(tester, '11-saved');
  });

  testWidgets('saved dark', (tester) async {
    await boot(tester, '/saved', dark: true, before: serveSaved);
    await _shot(tester, '12-saved-dark');
  });

  testWidgets('saved empty', (tester) async {
    await boot(
      tester,
      '/saved',
      before: (harness) => harness.appUserCubit.updateUser(sampleUser()),
    );
    await _shot(tester, '13-saved-empty');
  });

  testWidgets('article end dark', (tester) async {
    final harness = await boot(
      tester,
      '/view/a0',
      dark: true,
      before: serveEnd,
    );
    await toEnd(tester, harness);
    await _shot(tester, '14-article-end-dark');
  });

  testWidgets('sign in', (tester) async {
    await boot(tester, '/login');
    await _shot(tester, '15-login');
  });

  testWidgets('sign in dark', (tester) async {
    await boot(tester, '/login', dark: true);
    await _shot(tester, '16-login-dark');
  });

  testWidgets('sign up', (tester) async {
    await boot(tester, '/signup');
    await _shot(tester, '17-signup');
  });

  testWidgets('password recovery', (tester) async {
    await boot(tester, '/forgot-password');
    await _shot(tester, '18-recovery');
  });

  testWidgets('search', (tester) async {
    await boot(tester, '/search');
    await _shot(tester, '05-search');
  });

  testWidgets('profile', (tester) async {
    await boot(tester, '/profile');
    await _shot(tester, '06-profile');
  });

  testWidgets('home dark', (tester) async {
    await boot(tester, '/', dark: true);
    await _shot(tester, '07-home-dark');
  });

  testWidgets('article dark', (tester) async {
    await boot(tester, '/view/a0', dark: true);
    await _shot(tester, '08-article-dark');
  });
}
