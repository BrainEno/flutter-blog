// Temporary: renders a few real screens to PNG so the UI can be reviewed
// without a device. Run by .github/workflows/screens.yml, never by `flutter
// test` (it lives outside test/). Delete together with that workflow.
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:belog/features/notifications/domain/entities/notification_page.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:fpdart/fpdart.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../../test/support/locale_test_support.dart';
import '../../test/support/message_fakes.dart';
import '../../test/support/read_aloud_fakes.dart';
import '../../test/widget/read_aloud_navigation_test.dart' show installSpeech;
import '../../test/widget/router_test.dart' show Harness, sampleUser;

User _me() => User(
  id: 'user',
  email: 'lin@example.com',
  name: '林间',
  website: 'linjian.blog',
  updatedAt: DateTime.utc(2024),
);

class _History implements ReadingHistoryStore {
  @override
  Future<void> record({required String userId, required Blog blog}) async {}

  @override
  Future<List<ReadingHistoryEntry>> list({
    required String userId,
    int limit = 50,
  }) async => [
    for (final (i, t) in _titles.indexed)
      ReadingHistoryEntry(
        blogId: 'a$i',
        title: t,
        posterName: ['林间', '周默', 'Ada Lin', '许多'][i % 4],
        imageUrl: '',
        readAt: DateTime.now().subtract(Duration(hours: 5 * i + 1)),
        progress: [0.42, 1.0, null, 0.18, 0.7][i],
      ),
  ];

  @override
  Future<void> remove({required String userId, required String blogId}) async {}

  @override
  Future<void> clear({required String userId}) async {}

  @override
  Future<void> saveProgress({
    required String userId,
    required String blogId,
    required double progress,
  }) async {}

  @override
  Future<double?> progressOf({
    required String userId,
    required String blogId,
  }) async => blogId == 'a0' ? 0.42 : null;
}

class _Notifications implements NotificationRepository {
  final rows = <AppNotification>[
    for (final (i, kind) in [
      AppNotificationKind.articleCommented,
      AppNotificationKind.commentReplied,
      AppNotificationKind.articleLiked,
      AppNotificationKind.userFollowed,
      AppNotificationKind.messageReceived,
      AppNotificationKind.articleDeleted,
    ].indexed)
      AppNotification(
        id: 'n$i',
        eventKey: 'e$i',
        kind: kind,
        createdAt: DateTime.now().subtract(Duration(hours: 3 * i + 1)),
        readAt: i < 2 ? null : DateTime.now(),
        articleId: kind == AppNotificationKind.articleDeleted ? 'a9' : null,
        purgesAt: kind == AppNotificationKind.articleDeleted
            ? DateTime.now().add(const Duration(days: 30))
            : null,
        conversationId: kind == AppNotificationKind.messageReceived
            ? 'conversation-1'
            : null,
        articleSlug: 'a0',
        followerId: kind == AppNotificationKind.userFollowed ? 'u2' : null,
      ),
  ];

  @override
  Future<Either<Failure, NotificationPage>> list({
    required NowaveSessionFence fence,
    int limit = 50,
    String? cursor,
  }) async => right(NotificationPage(items: rows, nextCursor: null));

  @override
  Future<Either<Failure, AppNotification>> markRead(
    String id, {
    required NowaveSessionFence fence,
  }) async => right(rows.firstWhere((r) => r.id == id));

  @override
  Future<Either<Failure, int>> markAllRead({
    required NowaveSessionFence fence,
  }) async => right(0);

  @override
  Future<Either<Failure, int>> unreadCount({
    required NowaveSessionFence fence,
  }) async => right(2);
}

const _fonts = 'build/screens_fonts';

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
  // Asset images decode off the fake clock: wait for them for real, so a
  // cover is painted instead of the empty ink box it starts as.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump();
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

  void signIn(Harness harness) {
    harness.appUserCubit.updateUser(_me());
    GetIt.instance
      ..registerLazySingleton<ReadingHistoryStore>(_History.new)
      ..registerFactory<NotificationInboxCubit>(
        () => NotificationInboxCubit(
          repository: _Notifications(),
          identity: MessageTestIdentity()..userId = 'user',
        ),
      )
      ..registerFactory<MessageInboxCubit>(() {
        final repository = FakeMessageRepository()
          ..conversationsResult = [
            testConversation(
              id: 'c1',
              participants: const ['user', 'user-b'],
              unreadCount: 2,
              lastMessage: testMessage(
                id: 'm1',
                conversationId: 'c1',
                senderId: 'user-b',
                body: '那篇《没有写完的稿纸》我读了三遍，想问问结尾那句是怎么来的？',
                createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
              ),
              lastActivityAt: DateTime.now().subtract(
                const Duration(minutes: 20),
              ),
            ),
            testConversation(
              id: 'c2',
              participants: const ['user', 'user-c'],
              lastMessage: testMessage(
                id: 'm2',
                conversationId: 'c2',
                senderId: 'user',
                body: '好的，周末前发给你。',
                createdAt: DateTime.now().subtract(const Duration(days: 2)),
              ),
              lastActivityAt: DateTime.now().subtract(const Duration(days: 2)),
            ),
          ];
        return MessageInboxCubit(
          repository: repository,
          identity: MessageTestIdentity()..userId = 'user',
          names: FakeParticipantNames({'user-b': '周默', 'user-c': 'Ada Lin'}),
        );
      });
    when(
      () => harness.remote.isBlogLikedByUser(any(), any()),
    ).thenAnswer((_) async => false);
    when(
      () => harness.remote.getMyArticles(userId: any(named: 'userId')),
    ).thenAnswer(
      (_) async => [for (final (i, t) in _titles.indexed) _blog(i, t)],
    );
    when(
      () => harness.remote.getAuthorArticles(
        any(),
        kind: any(named: 'kind'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(
      (_) async => [for (final (i, t) in _titles.indexed) _blog(i, t)],
    );
  }

  testWidgets('profile', (tester) async {
    await boot(tester, '/profile', before: signIn);
    await _shot(tester, '20-profile');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '20b-profile-bottom');
  });

  testWidgets('profile dark', (tester) async {
    await boot(tester, '/profile', dark: true, before: signIn);
    await _shot(tester, '21-profile-dark');
  });

  testWidgets('history', (tester) async {
    await boot(tester, '/profile/history', before: signIn);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await _shot(tester, '22-history');
  });

  testWidgets('notifications', (tester) async {
    await boot(tester, '/profile/notifications', before: signIn);
    await _shot(tester, '23-notifications');
  });

  testWidgets('messages', (tester) async {
    await boot(tester, '/profile/messages', before: signIn);
    await _shot(tester, '24-messages');
  });

  testWidgets('author', (tester) async {
    await boot(tester, '/author/author', before: signIn);
    await _shot(tester, '25-author');
  });

  testWidgets('my articles', (tester) async {
    await boot(tester, '/profile/my-articles', before: signIn);
    await _shot(tester, '26-my-articles');
  });

  testWidgets('search results', (tester) async {
    await boot(
      tester,
      '/search',
      before: (harness) {
        signIn(harness);
        when(() => harness.remote.searchBlogs(any())).thenAnswer(
          (_) async => [for (final (i, t) in _titles.indexed) _blog(i, t)],
        );
      },
    );
    await tester.enterText(find.byType(TextField).first, '城市');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '27-search-results');
  });

  testWidgets('search empty', (tester) async {
    await boot(tester, '/search', before: signIn);
    await _shot(tester, '28-search');
  });

  testWidgets('article resume', (tester) async {
    await boot(tester, '/view/a0', before: signIn);
    await _shot(tester, '31-article-resume');
  });

  testWidgets('article resume dark', (tester) async {
    await boot(tester, '/view/a0', dark: true, before: signIn);
    await _shot(tester, '32-article-resume-dark');
  });

  testWidgets('about', (tester) async {
    await boot(tester, '/profile/about', before: signIn);
    await _shot(tester, '29-about');
  });
}
