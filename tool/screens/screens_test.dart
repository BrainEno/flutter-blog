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
import '../../test/widget/router_test.dart' show Harness;

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
    await _family('InterTight', [
      'assets/fonts/InterTight-Variable.ttf',
      '$_fonts/NotoSansSC.otf',
    ]);
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
