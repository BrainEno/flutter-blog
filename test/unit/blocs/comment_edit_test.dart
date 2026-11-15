import 'dart:async';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_edit_result.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _Get extends Mock implements GetComments {}

class _Create extends Mock implements CreateComment {}

class _Delete extends Mock implements DeleteComment {}

class _Edit extends Mock implements EditComment {}

class _Identity implements NowaveSessionIdentity {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  String? activeUserId = 'a';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 1;
  @override
  Stream<void> get identityChanges => changes.stream;
  void change(String? id) {
    activeUserId = id;
    sessionGeneration++;
    changes.add(null);
  }
}

Comment _comment(
  String id, {
  String content = 'before',
  String? parent,
  List<Comment> replies = const [],
  bool plain = true,
  String author = 'a',
  DateTime? editedAt,
}) => Comment(
  id: id,
  articleId: 'article',
  authorId: author,
  parentCommentId: parent,
  content: content,
  isPlainText: plain,
  createdAt: DateTime.utc(2025),
  editedAt: editedAt,
  replies: replies,
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _Get get;
  late _Edit edit;
  late _Identity identity;
  late CommentBloc bloc;
  late Comment child;
  setUpAll(
    () => registerFallbackValue(
      const NowaveSessionFence(userId: 'a', generation: 1),
    ),
  );
  setUp(() async {
    get = _Get();
    edit = _Edit();
    identity = _Identity();
    child = _comment(
      'child',
      parent: 'root',
      replies: [_comment('grandchild', parent: 'child')],
    );
    when(() => get('slug')).thenAnswer(
      (_) async => right(
        CommentPage(
          items: [
            _comment('root', replies: [child]),
          ],
          nextCursor: null,
        ),
      ),
    );
    bloc = CommentBloc(
      getComments: get,
      createComment: _Create(),
      deleteComment: _Delete(),
      slug: 'slug',
      sessionIdentity: identity,
      editComment: edit,
    );
    bloc.add(const CommentsRequested());
    await _tick();
  });
  tearDown(() async {
    await bloc.close();
    await identity.changes.close();
  });

  test(
    'updates a nested body without replacing replies and trims input',
    () async {
      when(
        () => edit(
          commentId: 'child',
          content: 'after',
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenAnswer(
        (_) async => right(
          _comment(
            'child',
            parent: 'root',
            content: 'after',
            editedAt: DateTime.utc(2026),
          ),
        ),
      );
      final result = await bloc.editPlainComment(
        original: child,
        text: ' after ',
        fence: bloc.captureFence()!,
      );
      await _tick();
      expect(result.status, CommentEditStatus.saved);
      final stored = bloc.state.comments.single.replies.single;
      expect(stored.content, 'after');
      expect(stored.replies.single.id, 'grandchild');
      expect(stored.parentCommentId, 'root');
    },
  );

  test('a stale or structured snapshot never reaches the API', () async {
    final fence = bloc.captureFence()!;
    expect(
      (await bloc.editPlainComment(
        original: _comment('child', parent: 'root', plain: false),
        text: 'after',
        fence: fence,
      )).status,
      CommentEditStatus.stale,
    );
    expect(
      (await bloc.editPlainComment(
        original: _comment('child', parent: 'root', content: 'old'),
        text: 'after',
        fence: fence,
      )).status,
      CommentEditStatus.stale,
    );
    verifyNever(
      () => edit(
        commentId: any(named: 'commentId'),
        content: any(named: 'content'),
        sessionFence: any(named: 'sessionFence'),
      ),
    );
  });

  test(
    'switching account drops a late success and invalidates the fence',
    () async {
      final gate = Completer<Either<Failure, Comment>>();
      when(
        () => edit(
          commentId: 'child',
          content: 'after',
          sessionFence: any(named: 'sessionFence'),
        ),
      ).thenAnswer((_) => gate.future);
      final pending = bloc.editPlainComment(
        original: child,
        text: 'after',
        fence: bloc.captureFence()!,
      );
      identity.change('b');
      await _tick();
      gate.complete(
        right(
          _comment(
            'child',
            parent: 'root',
            content: 'after',
            editedAt: DateTime.utc(2026),
          ),
        ),
      );
      expect((await pending).status, CommentEditStatus.sessionChanged);
      await _tick();
      expect(bloc.state.comments.single.replies.single.content, 'before');
    },
  );

  test('duplicate in-flight edits are blocked', () async {
    final gate = Completer<Either<Failure, Comment>>();
    when(
      () => edit(
        commentId: 'child',
        content: 'after',
        sessionFence: any(named: 'sessionFence'),
      ),
    ).thenAnswer((_) => gate.future);
    final fence = bloc.captureFence()!;
    final pending = bloc.editPlainComment(
      original: child,
      text: 'after',
      fence: fence,
    );
    final duplicate = await bloc.editPlainComment(
      original: child,
      text: 'after',
      fence: fence,
    );
    expect(duplicate.status, CommentEditStatus.stale);
    gate.complete(left(const Failure('unknown', code: 'comments.editUnknown')));
    expect((await pending).status, CommentEditStatus.outcomeUnknown);
    verify(
      () => edit(
        commentId: 'child',
        content: 'after',
        sessionFence: any(named: 'sessionFence'),
      ),
    ).called(1);
  });
}
