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
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/features/blog/presentation/comments/comment_tile.dart';
import 'package:belog/features/blog/presentation/comments/comment_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class MockGetComments extends Mock implements GetComments {}

class MockCreateComment extends Mock implements CreateComment {}

class MockDeleteComment extends Mock implements DeleteComment {}

class MockCommentBloc extends Mock implements CommentBloc {}

class MockUuid extends Mock implements Uuid {}

void _ignoreAuthor(String userId) {}

Comment _comment(
  String id, {
  String authorId = 'someone-else',
  String content = '写得真好',
  String? parentId,
  DateTime? editedAt,
  List<Comment> replies = const [],
}) => Comment(
  id: id,
  articleId: 'server-uuid-1',
  authorId: authorId,
  parentCommentId: parentId,
  content: content,
  createdAt: DateTime.utc(2025, 6, 1),
  editedAt: editedAt,
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
  double horizontalPadding = 0,
  VoidCallback? onRequestLogin,
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
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: CommentsSection(
                slug: 'my-slug',
                onOpenAuthor: _ignoreAuthor,
                onRequestLogin: onRequestLogin,
              ),
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
    registerFallbackValue(const CommentDeleteRequested('fallback'));
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

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'edited markers survive reply insertion and deletion at 320dp 2x in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          appUserCubit.updateUser(_user());
          final rootEdited = DateTime.utc(2026, 11, 10, 12);
          final childEdited = DateTime.utc(2026, 11, 11, 9, 5);
          when(() => getComments('my-slug')).thenAnswer(
            (_) async => right<Failure, CommentPage>(
              _page([
                _comment(
                  'root',
                  editedAt: rootEdited,
                  replies: [
                    _comment('child', parentId: 'root', editedAt: childEdited),
                  ],
                ),
                _comment('legacy', content: 'legacy body'),
              ]),
            ),
          );
          when(
            () => createComment(any(that: isA<CreateCommentParams>())),
          ).thenAnswer(
            (_) async => right<Failure, Comment>(
              _comment('new', parentId: 'root', content: 'new reply'),
            ),
          );
          when(
            () => deleteComment('child'),
          ).thenAnswer((_) async => right<Failure, void>(null));
          final bloc = buildBloc();
          addTearDown(bloc.close);
          await _pumpSection(
            tester,
            appUserCubit: appUserCubit,
            commentBloc: bloc,
            locale: locale,
            textScale: 2,
            horizontalPadding: 16,
          );
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.commentEdited), findsNWidgets(2));
          final legacy = find.byWidgetPredicate(
            (widget) => widget is CommentTile && widget.comment.id == 'legacy',
          );
          expect(
            find.descendant(
              of: legacy,
              matching: find.text(l10n.commentEdited),
            ),
            findsNothing,
          );
          await tester.ensureVisible(find.text(l10n.commentEdited).first);
          await tester.pumpAndSettle();
          final label = tester
              .getSemantics(find.text(l10n.commentEdited).first)
              .getSemanticsData()
              .label;
          expect(label, contains(l10n.commentEdited));
          expect(tester.takeException(), isNull);
          bloc.add(
            const CommentSubmitted(
              content: 'new reply',
              parentCommentId: 'root',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(l10n.commentEdited), findsNWidgets(2));
          expect(bloc.state.comments.first.editedAt, rootEdited);
          expect(bloc.state.comments.first.replies.first.editedAt, childEdited);
          expect(bloc.state.comments.first.createdAt, DateTime.utc(2025, 6, 1));
          bloc.add(const CommentDeleteRequested('child'));
          await tester.pumpAndSettle();
          expect(find.text(l10n.commentEdited), findsOneWidget);
          expect(bloc.state.comments.first.editedAt, rootEdited);
          expect(bloc.state.comments.first.replies.single.id, 'new');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('loads subsequent pages and stops after a short page', (
    tester,
  ) async {
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

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'guest reply opens login and never preselects a target in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          when(() => getComments('my-slug')).thenAnswer(
            (_) async => right<Failure, CommentPage>(
              _page([
                _comment(
                  'root',
                  replies: [_comment('child', parentId: 'root')],
                ),
              ]),
            ),
          );
          var loginRequests = 0;
          final bloc = buildBloc();
          addTearDown(bloc.close);
          await _pumpSection(
            tester,
            appUserCubit: appUserCubit,
            commentBloc: bloc,
            locale: locale,
            textScale: 2,
            horizontalPadding: 16,
            onRequestLogin: () => loginRequests++,
          );
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          final leaf = find.byWidgetPredicate(
            (widget) => widget is CommentTile && widget.comment.id == 'child',
          );
          final button = find.descendant(
            of: leaf,
            matching: find.widgetWithText(TextButton, l10n.signInToReply),
          );
          expect(find.text(l10n.signInToReply), findsNWidgets(2));
          expect(find.text(l10n.actionReply), findsNothing);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final data = tester.getSemantics(button).getSemanticsData();
          expect(data.label, contains(l10n.signInToReply));
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(loginRequests, 1);
          expect(find.byType(CommentComposer), findsNothing);
          verifyNever(
            () => createComment(any(that: isA<CreateCommentParams>())),
          );

          // Traverse from the first focusable element using only Tab, then Enter.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final text = find.descendant(
            of: button,
            matching: find.text(l10n.signInToReply),
          );
          for (var step = 0; step < 12; step++) {
            if (Focus.of(tester.element(text)).hasPrimaryFocus) break;
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(Focus.of(tester.element(text)).hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(loginRequests, 2);
          expect(tester.takeException(), isNull);

          appUserCubit.updateUser(_user());
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CommentComposer>(find.byType(CommentComposer))
                .replyTo,
            isNull,
          );
          final loggedInReply = find.descendant(
            of: leaf,
            matching: find.widgetWithText(TextButton, l10n.actionReply),
          );
          await tester.ensureVisible(loggedInReply);
          await tester.pumpAndSettle();
          await tester.tap(loggedInReply);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CommentComposer>(find.byType(CommentComposer))
                .replyTo
                ?.id,
            'child',
          );
          expect(loginRequests, 2);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets('guest reply is disabled without a login handler in $locale', (
      tester,
    ) async {
      when(() => getComments('my-slug')).thenAnswer(
        (_) async => right<Failure, CommentPage>(_page([_comment('root')])),
      );
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await _pumpSection(
        tester,
        appUserCubit: appUserCubit,
        commentBloc: bloc,
        locale: locale,
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final reply = find.widgetWithText(TextButton, l10n.signInToReply);
      expect(tester.widget<TextButton>(reply).onPressed, isNull);
      expect(find.byType(CommentComposer), findsNothing);
      verifyNever(() => createComment(any(that: isA<CreateCommentParams>())));
    });
  }

  testWidgets(
    'stale signed-in reply callback checks current identity before acting',
    (tester) async {
      appUserCubit.updateUser(_user());
      when(() => getComments('my-slug')).thenAnswer(
        (_) async => right<Failure, CommentPage>(_page([_comment('root')])),
      );
      var loginRequests = 0;
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await _pumpSection(
        tester,
        appUserCubit: appUserCubit,
        commentBloc: bloc,
        onRequestLogin: () => loginRequests++,
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final oldCallback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, l10n.actionReply))
          .onPressed!;
      appUserCubit.updateUser(null);
      oldCallback();
      await tester.pumpAndSettle();
      expect(loginRequests, 1);
      expect(find.byType(CommentComposer), findsNothing);
      appUserCubit.updateUser(_user());
      await tester.pumpAndSettle();
      expect(
        tester.widget<CommentComposer>(find.byType(CommentComposer)).replyTo,
        isNull,
      );
      verifyNever(() => createComment(any(that: isA<CreateCommentParams>())));
    },
  );

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

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'depth rejection preserves draft and supports another parent in $locale',
      (tester) async {
        appUserCubit.updateUser(_user());
        when(() => getComments('my-slug')).thenAnswer(
          (_) async => right<Failure, CommentPage>(
            _page([
              _comment(
                'root',
                content: 'root comment',
                replies: [
                  _comment('deep', content: 'deep comment', parentId: 'root'),
                ],
              ),
            ]),
          ),
        );
        var sequence = 0;
        when(() => uuid.v4()).thenAnswer((_) => 'key-${sequence++}');
        final requests = <CreateCommentParams>[];
        when(
          () => createComment(any(that: isA<CreateCommentParams>())),
        ).thenAnswer((invocation) async {
          final params =
              invocation.positionalArguments.single as CreateCommentParams;
          requests.add(params);
          if (params.parentCommentId == 'deep') {
            return left<Failure, Comment>(
              Failure(
                'safe fallback',
                kind: FailureKind.validation,
                code: 'comments.depthExceeded',
                cause: StateError('private backend detail'),
              ),
            );
          }
          return right<Failure, Comment>(
            _comment(
              'new',
              authorId: 'viewer-1',
              content: params.content,
              parentId: params.parentCommentId,
            ),
          );
        });
        final bloc = buildBloc();
        addTearDown(bloc.close);
        await _pumpSection(
          tester,
          appUserCubit: appUserCubit,
          commentBloc: bloc,
          locale: locale,
        );
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        final deep = find.byWidgetPredicate(
          (widget) => widget is CommentTile && widget.comment.id == 'deep',
        );
        final deepReply = find.descendant(
          of: deep,
          matching: find.widgetWithText(TextButton, l10n.actionReply),
        );
        await tester.ensureVisible(deepReply);
        await tester.pumpAndSettle();
        await tester.tap(deepReply);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'my preserved draft');
        final send = find.text(l10n.actionSend);
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(find.text(l10n.errorCommentDepthExceeded), findsOneWidget);
        expect(find.textContaining('private backend detail'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'my preserved draft',
        );
        expect(
          tester
              .widget<CommentComposer>(find.byType(CommentComposer))
              .replyTo
              ?.id,
          'deep',
        );
        expect(bloc.state.failure?.cause, isNull);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(requests.map((request) => request.idempotencyKey), [
          'key-0',
          'key-0',
        ]);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'my preserved draft',
        );
        final rootReply = find
            .widgetWithText(TextButton, l10n.actionReply)
            .first;
        await tester.ensureVisible(rootReply);
        await tester.pumpAndSettle();
        await tester.tap(rootReply);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CommentComposer>(find.byType(CommentComposer))
              .replyTo
              ?.id,
          'root',
        );
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(requests.map((request) => request.parentCommentId), [
          'deep',
          'deep',
          'root',
        ]);
        expect(requests.map((request) => request.idempotencyKey), [
          'key-0',
          'key-0',
          'key-1',
        ]);
        expect(
          requests.map((request) => request.content),
          everyElement('my preserved draft'),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(bloc.state.comments.single.replies.last.id, 'new');
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('cancelling delete keeps the comment', (tester) async {
    appUserCubit.updateUser(_user());
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        _page([_comment('own', authorId: 'viewer-1', content: 'own comment')]),
      ),
    );
    final bloc = buildBloc();
    addTearDown(bloc.close);
    await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('own comment'), findsOneWidget);
    verifyNever(() => deleteComment(any()));
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    'sign out',
    'different account',
    'same account refreshed',
    'switch away and back',
  ]) {
    testWidgets('delete confirmation is invalidated by $scenario', (
      tester,
    ) async {
      appUserCubit.updateUser(_user());
      when(() => getComments('my-slug')).thenAnswer(
        (_) async => right<Failure, CommentPage>(
          _page([
            _comment('own', authorId: 'viewer-1', content: 'own comment'),
          ]),
        ),
      );
      when(
        () => deleteComment('own'),
      ).thenAnswer((_) async => right<Failure, void>(null));
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除评论'), findsOneWidget);
      final other = User(
        id: 'viewer-2',
        email: 'other@example.invalid',
        name: 'Other',
        updatedAt: DateTime.utc(2024),
      );
      switch (scenario) {
        case 'sign out':
          appUserCubit.updateUser(null);
        case 'different account':
          appUserCubit.updateUser(other);
        case 'same account refreshed':
          appUserCubit.updateUser(_user());
        case 'switch away and back':
          appUserCubit.updateUser(other);
          appUserCubit.updateUser(_user());
      }
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await tester.pumpAndSettle();
      verifyNever(() => deleteComment(any()));
      expect(find.text('own comment'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A fresh confirmation by the owner remains effective.
      appUserCubit.updateUser(_user());
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await tester.pumpAndSettle();
      verify(() => deleteComment('own')).called(1);
      expect(find.text('own comment'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a stale delete callback cannot open a confirmation after identity changes',
    (tester) async {
      appUserCubit.updateUser(_user());
      when(() => getComments('my-slug')).thenAnswer(
        (_) async => right<Failure, CommentPage>(
          _page([_comment('own', authorId: 'viewer-1')]),
        ),
      );
      final bloc = buildBloc();
      addTearDown(bloc.close);
      await _pumpSection(tester, appUserCubit: appUserCubit, commentBloc: bloc);
      await tester.pumpAndSettle();
      final old = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '删除'))
          .onPressed!;
      appUserCubit.updateUser(_user());
      old();
      await tester.pumpAndSettle();
      expect(find.text('删除评论'), findsNothing);
      verifyNever(() => deleteComment(any()));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a confirmed delete cannot dispatch after its row is unmounted', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final confirmation = Completer<bool>();
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
            body: CommentTile(
              comment: _comment('own', authorId: 'viewer-1'),
              depth: 0,
              onReply: (_) {},
              replyRequiresLogin: false,
              onOpenAuthor: _ignoreAuthor,
              confirmDelete: () => confirmation.future,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    confirmation.complete(true);
    await tester.pumpAndSettle();
    verifyNever(() => deleteComment(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a confirmed delete cannot dispatch to a closed bloc', (
    tester,
  ) async {
    appUserCubit.updateUser(_user());
    var closed = false;
    final bloc = MockCommentBloc();
    when(() => bloc.state).thenReturn(const CommentState());
    when(
      () => bloc.stream,
    ).thenAnswer((_) => const Stream<CommentState>.empty());
    when(() => bloc.isClosed).thenAnswer((_) => closed);
    final confirmation = Completer<bool>();
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
            body: CommentTile(
              comment: _comment('own', authorId: 'viewer-1'),
              depth: 0,
              onReply: (_) {},
              replyRequiresLogin: false,
              onOpenAuthor: _ignoreAuthor,
              confirmDelete: () => confirmation.future,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump();
    closed = true;
    confirmation.complete(true);
    await tester.pumpAndSettle();
    expect(bloc.isClosed, isTrue);
    verifyNever(() => bloc.add(any()));
    expect(tester.takeException(), isNull);
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
  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'deep and legacy replies remain usable at 320dp and 2x in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        appUserCubit.updateUser(_user());

        // Depth 12 also exercises threads created before the current write cap.
        var thread = _comment(
          'c12',
          authorId: 'viewer-1',
          content: 'deepest body',
          parentId: 'c11',
        );
        for (var depth = 11; depth >= 0; depth--) {
          thread = _comment(
            'c$depth',
            content: 'body $depth',
            parentId: depth == 0 ? null : 'c${depth - 1}',
            replies: [thread],
          );
        }
        when(
          () => getComments('my-slug'),
        ).thenAnswer((_) async => right<Failure, CommentPage>(_page([thread])));
        when(
          () => deleteComment('c12'),
        ).thenAnswer((_) async => right<Failure, void>(null));
        final bloc = buildBloc();
        addTearDown(bloc.close);
        await _pumpSection(
          tester,
          appUserCubit: appUserCubit,
          commentBloc: bloc,
          locale: locale,
          textScale: 2,
          horizontalPadding: 16,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CommentTile), findsNWidgets(13));
        expect(find.text('deepest body'), findsOneWidget);
        final leaf = find.byWidgetPredicate(
          (widget) => widget is CommentTile && widget.comment.id == 'c12',
        );
        expect(tester.getSize(leaf).width, greaterThan(150));
        final l10n = lookupAppLocalizations(locale);
        final reply = find.descendant(
          of: leaf,
          matching: find.widgetWithText(TextButton, l10n.actionReply),
        );
        await tester.ensureVisible(reply);
        await tester.pumpAndSettle();
        expect(reply.hitTestable(), findsOneWidget);
        await tester.tap(reply);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CommentComposer>(find.byType(CommentComposer))
              .replyTo
              ?.id,
          'c12',
        );
        expect(tester.takeException(), isNull);

        final delete = find.descendant(
          of: leaf,
          matching: find.widgetWithText(TextButton, l10n.actionDelete),
        );
        await tester.ensureVisible(delete);
        await tester.pumpAndSettle();
        expect(delete.hitTestable(), findsOneWidget);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        verifyNever(() => deleteComment(any()));
        expect(find.text(l10n.commentDeleteTitle), findsOneWidget);
        await tester.tap(
          find.widgetWithText(TextButton, l10n.actionDelete).last,
        );
        await tester.pumpAndSettle();
        verify(() => deleteComment('c12')).called(1);
        expect(find.text('deepest body'), findsNothing);
        expect(find.byType(CommentTile), findsNWidgets(12));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
