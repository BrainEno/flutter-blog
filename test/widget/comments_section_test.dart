import 'dart:async';

import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class MockGetComments extends Mock implements GetComments {}

class MockCreateComment extends Mock implements CreateComment {}

class MockDeleteComment extends Mock implements DeleteComment {}

class MockUuid extends Mock implements Uuid {}

void _ignoreAuthor(String userId) {}

Comment _comment(
  String id, {
  String authorId = 'someone-else',
  String content = '写得真好',
  String? parentId,
  List<Comment> replies = const [],
}) => Comment(
  id: id,
  articleId: 'server-uuid-1',
  authorId: authorId,
  parentCommentId: parentId,
  content: content,
  createdAt: DateTime.utc(2025, 6, 1),
  replies: replies,
);

CommentPage _page(List<Comment> items, {String? cursor}) =>
    CommentPage(items: items, nextCursor: cursor);

User _user() => User(
  id: 'viewer-1',
  email: 'viewer@example.invalid',
  name: '读者',
  updatedAt: DateTime.utc(2024),
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required AppUserCubit appUserCubit,
  required CommentBloc commentBloc,
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) {
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AppUserCubit>.value(value: appUserCubit),
        BlocProvider<CommentBloc>.value(value: commentBloc),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: textScale == 1
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: CommentsSection(
              slug: 'my-slug',
              onOpenAuthor: _ignoreAuthor,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late MockGetComments getComments;
  late MockCreateComment createComment;
  late MockDeleteComment deleteComment;
  late AppUserCubit appUserCubit;
  late MockUuid uuid;

  setUpAll(() {
    registerFallbackValue(
      CreateCommentParams(slug: '', content: '', idempotencyKey: ''),
    );
  });

  setUp(() {
    getComments = MockGetComments();
    createComment = MockCreateComment();
    deleteComment = MockDeleteComment();
    appUserCubit = AppUserCubit();
    uuid = MockUuid();
    when(() => uuid.v4()).thenAnswer((_) => 'key-0');
  });

  tearDown(() async {
    await appUserCubit.close();
  });

  /// The bloc must be created inside the test body: its event queue is
  /// zone-bound, so a bloc built in setUp (outside the widget test's
  /// fake-async zone) would never deliver events and the section would
  /// spin its loading indicator forever.
  CommentBloc buildBloc() => CommentBloc(
    getComments: getComments,
    createComment: createComment,
    deleteComment: deleteComment,
    slug: 'my-slug',
    uuidGenerator: uuid,
  );

  testWidgets('renders the thread with nested replies (plain text)', (
    tester,
  ) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([
          _comment(
            'c1',
            replies: [_comment('c2', content: '同感', parentId: 'c1')],
          ),
          _comment('c3', content: '沙发'),
        ]),
      ),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('写得真好'), findsOneWidget);
    expect(find.text('同感'), findsOneWidget);
    expect(find.text('沙发'), findsOneWidget);
    // Two roots + one nested reply share the same neutral portrait component.
    expect(find.text('已加载 3 条'), findsOneWidget);
    expect(find.byType(NoWaveAvatar), findsNWidgets(3));
  });

  testWidgets('loads subsequent pages and stops after a short page', (tester) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', content: '评论c1')], cursor: 'cursor-1'),
      ),
    );
    when(() => getComments('my-slug', cursor: 'cursor-1')).thenAnswer(
      (_) async =>
          right<Failure, CommentPage>(_page([_comment('c2', content: '评论c2')])),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('已加载 1 条'), findsOneWidget);
    expect(find.text('加载更多评论'), findsOneWidget);
    await tester.ensureVisible(find.text('加载更多评论'));
    await tester.tap(find.text('加载更多评论'));
    await tester.pumpAndSettle();

    expect(find.text('评论c2'), findsOneWidget);
    expect(find.text('已加载 2 条'), findsOneWidget);
    expect(find.text('加载更多评论'), findsNothing);
  });

  testWidgets('pagination remains available after deleting the loaded rows', (
    tester,
  ) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1')], cursor: 'cursor-1'),
      ),
    );
    when(
      () => deleteComment('c1'),
    ).thenAnswer((_) async => right<Failure, void>(null));

    final bloc = buildBloc();
    addTearDown(bloc.close);
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    bloc.add(const CommentDeleteRequested('c1'));
    await tester.pumpAndSettle();

    expect(find.text('还没有评论，来说第一句吧'), findsOneWidget);
    expect(find.text('加载更多评论'), findsOneWidget);
  });

  testWidgets('a failed continuation page keeps rows and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', content: '评论c1')], cursor: 'cursor-1'),
      ),
    );
    when(() => getComments('my-slug', cursor: 'cursor-1')).thenAnswer((
      _,
    ) async {
      attempts++;
      if (attempts == 1) {
        return left<Failure, CommentPage>(
          Failure('网络暂时不可用', code: 'network.unavailable'),
        );
      }
      return right<Failure, CommentPage>(
        _page([_comment('c2', content: '评论c2')]),
      );
    });

    final bloc = buildBloc();
    addTearDown(bloc.close);
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('加载更多评论'));
    await tester.tap(find.text('加载更多评论'));
    await tester.pumpAndSettle();
    expect(find.text('评论c1'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('评论c2'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('pagination loading uses the No Wave label', (tester) async {
    final continuationPage = Completer<Either<Failure, CommentPage>>();
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', content: '评论c1')], cursor: 'cursor-1'),
      ),
    );
    when(
      () => getComments('my-slug', cursor: 'cursor-1'),
    ).thenAnswer((_) => continuationPage.future);

    final bloc = buildBloc();
    addTearDown(() async {
      if (!continuationPage.isCompleted) {
        continuationPage.complete(right<Failure, CommentPage>(_page([])));
      }
      await bloc.close();
    });
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('加载更多评论'));
    await tester.tap(find.text('加载更多评论'));
    await tester.pump();
    expect(find.byType(NoWaveLoadingLabel), findsOneWidget);

    continuationPage.complete(
      right<Failure, CommentPage>(_page([_comment('c2', content: '评论c2')])),
    );
    await tester.pumpAndSettle();
    expect(find.text('评论c2'), findsOneWidget);
  });

  testWidgets('a cursor-blind server shows a localized compatibility notice', (
    tester,
  ) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', content: '评论c1')], cursor: 'cursor-1'),
      ),
    );
    when(() => getComments('my-slug', cursor: 'cursor-1')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', content: '评论c1')], cursor: 'cursor-1'),
      ),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('加载更多评论'));
    await tester.tap(find.text('加载更多评论'));
    await tester.pumpAndSettle();

    expect(find.text('评论c1'), findsOneWidget);
    expect(find.text('此服务器暂不支持继续加载评论。'), findsOneWidget);
    expect(find.text('加载更多评论'), findsNothing);
  });

  testWidgets('comment and reply portraits delegate author selection', (
    tester,
  ) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([
          _comment(
            'c1',
            authorId: 'first-author',
            replies: [_comment('c2', authorId: 'reply-author', parentId: 'c1')],
          ),
        ]),
      ),
    );
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final opened = <String>[];
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppUserCubit>.value(value: appUserCubit),
          BlocProvider<CommentBloc>.value(value: bloc),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommentsSection(slug: 'my-slug', onOpenAuthor: opened.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoWaveAvatar).first);
    await tester.tap(find.byType(NoWaveAvatar).last);
    expect(opened, ['first-author', 'reply-author']);
  });

  testWidgets('signed-out readers see the login prompt, no composer', (
    tester,
  ) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, CommentPage>(_page(const [])));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('登录后即可参与评论'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('还没有评论，来说第一句吧'), findsOneWidget);
  });

  testWidgets('the login prompt routes through onRequestLogin', (tester) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, CommentPage>(_page(const [])));
    var requested = false;
    final bloc = buildBloc();
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppUserCubit>.value(value: appUserCubit),
          BlocProvider<CommentBloc>.value(value: bloc),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,

          home: Scaffold(
            body: CommentsSection(
              slug: 'my-slug',
              onOpenAuthor: _ignoreAuthor,
              onRequestLogin: () => requested = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('去登录'));
    expect(requested, isTrue);
  });

  testWidgets('a signed-in reader can submit a comment', (tester) async {
    appUserCubit.updateUser(_user());
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, CommentPage>(_page(const [])));
    when(() => createComment(any(that: isA<CreateCommentParams>()))).thenAnswer(
      (_) async => right<Failure, Comment>(
        _comment('c9', authorId: 'viewer-1', content: '我来抢沙发'),
      ),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我来抢沙发');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    verify(
      () => createComment(any(that: isA<CreateCommentParams>())),
    ).called(1);
    // The composer cleared and the comment appeared in the tree.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(find.text('我来抢沙发'), findsOneWidget);
  });

  testWidgets('reply mode shows the target and nests on submit', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(_page([_comment('c1')])),
    );
    when(() => createComment(any(that: isA<CreateCommentParams>()))).thenAnswer(
      (_) async => right<Failure, Comment>(
        _comment('c2', authorId: 'viewer-1', content: '回复内容', parentId: 'c1'),
      ),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('回复 @'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '回复内容');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    final captured =
        verify(
              () => createComment(captureAny(that: isA<CreateCommentParams>())),
            ).captured.single
            as CreateCommentParams;
    expect(captured.parentCommentId, 'c1');
    expect(find.textContaining('回复 @'), findsNothing);
  });

  testWidgets('deleting an own comment asks for confirmation first', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('c1', authorId: 'viewer-1', content: '我自己说的')]),
      ),
    );
    when(
      () => deleteComment('c1'),
    ).thenAnswer((_) async => right<Failure, void>(null));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    // Only the author's own comment shows the delete action.
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除评论'), findsOneWidget);
    verifyNever(() => deleteComment(any()));

    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await tester.pumpAndSettle();

    verify(() => deleteComment('c1')).called(1);
    expect(find.text('我自己说的'), findsNothing);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => left<Failure, CommentPage>(Failure('评论加载失败')));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('评论加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('an English reader sees localized comment copy, not Chinese', (
    tester,
  ) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => left<Failure, CommentPage>(Failure('评论加载失败')));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(
      tester,
      appUserCubit: appUserCubit,
      commentBloc: bloc,
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('评论加载失败'), findsNothing, reason: '英文界面不能回落到中文兜底文案');
  });

  testWidgets('the empty state is localized in English too', (tester) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, CommentPage>(_page(const [])));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(
      tester,
      appUserCubit: appUserCubit,
      commentBloc: bloc,
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No comments yet — be the first to speak'),
      findsOneWidget,
    );
    expect(find.text('评论'), findsNothing);
  });

  testWidgets('a thread survives 2x text on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([
          _comment(
            'c1',
            replies: [_comment('c2', content: '同感', parentId: 'c1')],
          ),
        ]),
      ),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(
      tester,
      appUserCubit: appUserCubit,
      commentBloc: bloc,
      textScale: 2,
    );
    await tester.pumpAndSettle();

    expect(find.text('写得真好'), findsOneWidget);
    expect(find.text('同感'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
