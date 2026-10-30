import 'package:belog/l10n/app_localizations.dart';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
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
}) {
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AppUserCubit>.value(value: appUserCubit),
        BlocProvider<CommentBloc>.value(value: commentBloc),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,

        home: Scaffold(body: SingleChildScrollView(child: CommentsSection(slug: 'my-slug'))),
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
      (_) async => right<Failure, List<Comment>>([
        _comment(
          'c1',
          replies: [_comment('c2', content: '同感', parentId: 'c1')],
        ),
        _comment('c3', content: '沙发'),
      ]),
    );

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('写得真好'), findsOneWidget);
    expect(find.text('同感'), findsOneWidget);
    expect(find.text('沙发'), findsOneWidget);
    // Two roots + one nested reply.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('signed-out readers see the login prompt, no composer', (
    tester,
  ) async {
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, List<Comment>>(const []));

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
    ).thenAnswer((_) async => right<Failure, List<Comment>>(const []));
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
    ).thenAnswer((_) async => right<Failure, List<Comment>>(const []));
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
    when(
      () => getComments('my-slug'),
    ).thenAnswer((_) async => right<Failure, List<Comment>>([_comment('c1')]));
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
      (_) async => right<Failure, List<Comment>>([
        _comment('c1', authorId: 'viewer-1', content: '我自己说的'),
      ]),
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
    ).thenAnswer((_) async => left<Failure, List<Comment>>(Failure('评论加载失败')));

    final bloc = buildBloc();
    addTearDown(bloc.close);

    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();

    expect(find.text('评论加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
