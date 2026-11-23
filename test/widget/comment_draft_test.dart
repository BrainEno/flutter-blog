import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/repositories/comment_draft_store.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/comments/comment_composer.dart';
import 'package:belog/features/blog/presentation/widgets/comments_section.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? get activeUserId => 'viewer-1';
  @override
  String? get accessToken => 'token';
  @override
  int get sessionGeneration => 1;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

class _GetComments extends Mock implements GetComments {}

class _CreateComment extends Mock implements CreateComment {}

class _DeleteComment extends Mock implements DeleteComment {}

class _Uuid extends Mock implements Uuid {}

/// Drafts in memory, keyed `user/slug`.
class _Store implements CommentDraftStore {
  final saved = <String, CommentDraft>{};

  @override
  Future<CommentDraft?> load({
    required String userId,
    required String slug,
  }) async => saved['$userId/$slug'];

  @override
  Future<void> save({
    required String userId,
    required String slug,
    required CommentDraft draft,
  }) async {
    if (draft.isBlank) {
      saved.remove('$userId/$slug');
    } else {
      saved['$userId/$slug'] = draft;
    }
  }
}

void _ignoreAuthor(String userId) {}

User _user(String id) => User(
  id: id,
  email: '$id@example.invalid',
  name: id,
  updatedAt: DateTime.utc(2024),
);

Comment _comment(String id, {String authorName = ''}) => Comment(
  id: id,
  articleId: 'server-uuid-1',
  authorId: 'someone-else',
  content: '写得真好',
  authorName: authorName,
  createdAt: DateTime.utc(2025, 6, 1),
);

void main() {
  late _GetComments getComments;
  late _CreateComment createComment;
  late _Uuid uuid;
  late AppUserCubit users;
  late _Store store;

  setUpAll(() {
    registerFallbackValue(
      CreateCommentParams(slug: '', content: '', idempotencyKey: ''),
    );
  });

  setUp(() {
    getComments = _GetComments();
    createComment = _CreateComment();
    uuid = _Uuid();
    when(() => uuid.v4()).thenAnswer((_) => 'key-0');
    users = AppUserCubit()..updateUser(_user('viewer-1'));
    store = _Store();
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        CommentPage(items: const [], nextCursor: null),
      ),
    );
  });

  tearDown(() => users.close());

  /// Built inside each test body: the bloc's event queue is zone-bound.
  CommentBloc bloc() {
    final bloc = CommentBloc(
      getComments: getComments,
      createComment: createComment,
      deleteComment: _DeleteComment(),
      slug: 'my-slug',
      uuidGenerator: uuid,
      sessionIdentity: _Identity(),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  /// The article page with its comments, or (when [open] is false) the
  /// reader somewhere else.
  Future<void> pump(WidgetTester tester, {bool open = true}) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppUserCubit>.value(value: users),
          BlocProvider<CommentBloc>.value(value: bloc()),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: open
                ? SingleChildScrollView(
                    child: CommentsSection(
                      slug: 'my-slug',
                      onOpenAuthor: _ignoreAuthor,
                      draftStore: store,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String box(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  final l10n = lookupAppLocalizations(const Locale('zh'));

  testWidgets('unsent typing is kept and is back on the next visit', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '还没写完的想法');
    await tester.pump(AppDurations.commentDraftSave);
    expect(store.saved['viewer-1/my-slug']?.text, '还没写完的想法');
    // Nothing to say about a draft the reader is writing right now.
    expect(find.text(l10n.commentDraftRestored), findsNothing);

    await pump(tester, open: false);
    await pump(tester);
    expect(box(tester), '还没写完的想法');
    expect(find.text(l10n.commentDraftRestored), findsOneWidget);

    // Typing on makes it the reader's again: the note goes.
    await tester.enterText(find.byType(TextField), '还没写完的想法，续');
    await tester.pump();
    expect(find.text(l10n.commentDraftRestored), findsNothing);
  });

  testWidgets('leaving the article keeps the typing at once', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '刚打的字');
    await pump(tester, open: false);
    expect(store.saved['viewer-1/my-slug']?.text, '刚打的字');
  });

  testWidgets('a restored draft can be discarded, and the discard undone', (
    tester,
  ) async {
    store.saved['viewer-1/my-slug'] = const CommentDraft(text: '旧草稿');
    await pump(tester);
    expect(box(tester), '旧草稿');

    await tester.tap(find.text(l10n.commentDraftDiscard));
    await tester.pumpAndSettle();
    expect(box(tester), isEmpty);
    expect(store.saved, isEmpty);
    expect(find.text(l10n.commentDraftDiscarded), findsOneWidget);

    await tester.tap(find.text(l10n.actionUndo));
    await tester.pumpAndSettle();
    expect(box(tester), '旧草稿');
    expect(store.saved['viewer-1/my-slug']?.text, '旧草稿');
  });

  testWidgets('a sent comment is no longer a draft', (tester) async {
    when(
      () => createComment(any()),
    ).thenAnswer((_) async => right<Failure, Comment>(_comment('c9')));
    await pump(tester);
    await tester.enterText(find.byType(TextField), '发出去');
    await tester.pump(AppDurations.commentDraftSave);
    expect(store.saved, isNotEmpty);

    await tester.tap(find.text(l10n.actionSend));
    await tester.pumpAndSettle();
    expect(box(tester), isEmpty);
    expect(store.saved, isEmpty);
  });

  testWidgets('a failed send keeps the draft', (tester) async {
    when(
      () => createComment(any()),
    ).thenAnswer((_) async => left<Failure, Comment>(Failure.networkOffline()));
    await pump(tester);
    await tester.enterText(find.byType(TextField), '网络不好');
    await tester.tap(find.text(l10n.actionSend));
    await tester.pumpAndSettle();
    await tester.pump(AppDurations.commentDraftSave);
    expect(box(tester), '网络不好');
    expect(store.saved['viewer-1/my-slug']?.text, '网络不好');
  });

  testWidgets('a reply comes back answering the same comment', (tester) async {
    when(() => getComments('my-slug')).thenAnswer(
      (_) async => right<Failure, CommentPage>(
        CommentPage(
          items: [_comment('c1', authorName: '阿博')],
          nextCursor: null,
        ),
      ),
    );
    await pump(tester);
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '同意');
    await pump(tester, open: false);
    expect(store.saved['viewer-1/my-slug']?.parentCommentId, 'c1');
    expect(store.saved['viewer-1/my-slug']?.parentAuthorName, '阿博');

    await pump(tester);
    expect(box(tester), '同意');
    final composer = tester.widget<CommentComposer>(
      find.byType(CommentComposer),
    );
    expect(composer.replyTo?.id, 'c1');
    expect(find.text(l10n.replyToLabel('阿博')), findsOneWidget);
  });

  testWidgets('a reply to a comment not loaded yet still names it', (
    tester,
  ) async {
    store.saved['viewer-1/my-slug'] = const CommentDraft(
      text: '接着说',
      parentCommentId: 'far-away',
      parentAuthorName: '阿博',
    );
    await pump(tester);
    expect(box(tester), '接着说');
    expect(
      tester.widget<CommentComposer>(find.byType(CommentComposer)).replyTo?.id,
      'far-away',
    );
    expect(find.text(l10n.replyToLabel('阿博')), findsOneWidget);

    // Cancelling the reply is a change worth keeping.
    await tester.tap(find.byTooltip(l10n.cancelReplyTooltip));
    await tester.pump(AppDurations.commentDraftSave);
    expect(store.saved['viewer-1/my-slug']?.parentCommentId, isNull);
    expect(store.saved['viewer-1/my-slug']?.text, '接着说');
  });

  testWidgets('another account never sees the draft', (tester) async {
    store.saved['viewer-2/my-slug'] = const CommentDraft(text: '二号的');
    await pump(tester);
    await tester.enterText(find.byType(TextField), '一号的');

    users.updateUser(_user('viewer-2'));
    await tester.pumpAndSettle();
    expect(box(tester), '二号的');
    expect(store.saved['viewer-1/my-slug']?.text, '一号的');

    users.updateUser(null);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    users.updateUser(_user('viewer-1'));
    await tester.pumpAndSettle();
    expect(box(tester), '一号的');
    expect(store.saved['viewer-2/my-slug']?.text, '二号的');
  });
}
