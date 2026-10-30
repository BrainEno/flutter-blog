import 'package:belog/core/error/failures.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class MockGetComments extends Mock implements GetComments {}

class MockCreateComment extends Mock implements CreateComment {}

class MockDeleteComment extends Mock implements DeleteComment {}

class FakeUuid extends Fake implements Uuid {
  int _counter = 0;
  @override
  String v4() => 'key-${_counter++}';
}

Comment _comment(String id, {String? parentId}) => Comment(
  id: id,
  articleId: 'server-uuid-1',
  authorId: 'u1',
  parentCommentId: parentId,
  content: '评论$id',
  createdAt: DateTime.utc(2025, 6, 1),
);

void main() {
  late MockGetComments getComments;
  late MockCreateComment createComment;
  late MockDeleteComment deleteComment;
  late FakeUuid uuid;
  late CommentBloc bloc;

  setUpAll(() {
    registerFallbackValue(
      CreateCommentParams(slug: '', content: '', idempotencyKey: ''),
    );
  });

  setUp(() {
    getComments = MockGetComments();
    createComment = MockCreateComment();
    deleteComment = MockDeleteComment();
    uuid = FakeUuid();
    bloc = CommentBloc(
      getComments: getComments,
      createComment: createComment,
      deleteComment: deleteComment,
      slug: 'my-slug',
      uuidGenerator: uuid,
    );
  });

  tearDown(() => bloc.close());

  group('CommentsRequested', () {
    test('loads the thread into the loaded state', () async {
      when(
        () => getComments('my-slug'),
      ).thenAnswer(
        (_) async => right<Failure, List<Comment>>([_comment('c1')]),
      );

      bloc.add(const CommentsRequested());
      await bloc.close();

      expect(bloc.state.status, CommentListStatus.loaded);
      expect(bloc.state.comments.map((c) => c.id), ['c1']);
      expect(bloc.state.totalCount, 1);
    });

    test('a failed load reports a failure state with the message', () async {
      when(() => getComments('my-slug')).thenAnswer(
        (_) async => left<Failure, List<Comment>>(Failure('评论加载失败')),
      );

      bloc.add(const CommentsRequested());
      await bloc.close();

      expect(bloc.state.status, CommentListStatus.failure);
      expect(bloc.state.error, '评论加载失败');
    });
  });

  group('CommentSubmitted', () {
    test('appends a root comment and clears the submitting flag', () async {
      when(
        () => getComments('my-slug'),
      ).thenAnswer(
        (_) async => right<Failure, List<Comment>>([_comment('c1')]),
      );
      bloc.add(const CommentsRequested());
      await Future<void>.delayed(Duration.zero);

      when(
        () => createComment(any(that: isA<CreateCommentParams>())),
      ).thenAnswer(
        (_) async => right<Failure, Comment>(_comment('c2')),
      );

      bloc.add(const CommentSubmitted(content: '新评论'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.submitting, isFalse);
      expect(bloc.state.comments.map((c) => c.id), ['c1', 'c2']);
    });

    test('nests a reply under its direct parent', () async {
      when(
        () => getComments('my-slug'),
      ).thenAnswer(
        (_) async => right<Failure, List<Comment>>([_comment('c1')]),
      );
      bloc.add(const CommentsRequested());
      await Future<void>.delayed(Duration.zero);

      when(
        () => createComment(any(that: isA<CreateCommentParams>())),
      ).thenAnswer(
        (_) async => right<Failure, Comment>(_comment('c2', parentId: 'c1')),
      );

      bloc.add(const CommentSubmitted(content: '回复', parentCommentId: 'c1'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.comments.first.replies.map((c) => c.id), ['c2']);
      expect(bloc.state.totalCount, 2);
    });

    test('retries with the same idempotency key after a failure', () async {
      final keys = <String>[];
      when(
        () => createComment(any(that: isA<CreateCommentParams>())),
      ).thenAnswer((invocation) async {
        final params = invocation.positionalArguments.single
            as CreateCommentParams;
        keys.add(params.idempotencyKey);
        // First attempt fails, retry succeeds.
        if (keys.length == 1) {
          return left<Failure, Comment>(Failure('网络超时'));
        }
        return right<Failure, Comment>(_comment('c2'));
      });

      bloc.add(const CommentSubmitted(content: '第一条'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.error, '网络超时');
      expect(bloc.state.comments, isEmpty);

      bloc.add(const CommentSubmitted(content: '第一条'));
      await Future<void>.delayed(Duration.zero);

      expect(keys, ['key-0', 'key-0']);
      expect(bloc.state.error, isEmpty);
      expect(bloc.state.comments.map((c) => c.id), ['c2']);
    });

    test('a changed text mints a fresh idempotency key', () async {
      final keys = <String>[];
      when(
        () => createComment(any(that: isA<CreateCommentParams>())),
      ).thenAnswer((invocation) async {
        final params = invocation.positionalArguments.single
            as CreateCommentParams;
        keys.add(params.idempotencyKey);
        return left<Failure, Comment>(Failure('网络超时'));
      });

      bloc.add(const CommentSubmitted(content: '第一条'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const CommentSubmitted(content: '改了主意'));
      await Future<void>.delayed(Duration.zero);

      expect(keys, ['key-0', 'key-1']);
    });

    test('empty and over-long content never reaches the server', () async {
      bloc.add(const CommentSubmitted(content: '   '));
      bloc.add(
        CommentSubmitted(content: 'x' * (CommentBloc.maxContentLength + 1)),
      );
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => createComment(any(that: isA<CreateCommentParams>())),
      );
    });
  });

  group('CommentDeleteRequested', () {
    test('removes the comment and its reply subtree', () async {
      final c1 = _comment('c1');
      final withReplies = Comment(
        id: 'c1',
        articleId: c1.articleId,
        authorId: c1.authorId,
        content: c1.content,
        createdAt: c1.createdAt,
        replies: [_comment('c2', parentId: 'c1')],
      );
      when(
        () => getComments('my-slug'),
      ).thenAnswer((_) async => right<Failure, List<Comment>>([withReplies]));
      bloc.add(const CommentsRequested());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.totalCount, 2);

      when(
        () => deleteComment('c1'),
      ).thenAnswer((_) async => right<Failure, void>(null));

      bloc.add(const CommentDeleteRequested('c1'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.comments, isEmpty);
      expect(bloc.state.totalCount, 0);
      expect(bloc.state.deletingIds, isEmpty);
    });

    test('a failed delete keeps the comment and reports the error', () async {
      when(
        () => getComments('my-slug'),
      ).thenAnswer(
        (_) async => right<Failure, List<Comment>>([_comment('c1')]),
      );
      bloc.add(const CommentsRequested());
      await Future<void>.delayed(Duration.zero);

      when(
        () => deleteComment('c1'),
      ).thenAnswer((_) async => left<Failure, void>(Failure('评论删除失败')));

      bloc.add(const CommentDeleteRequested('c1'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.comments.map((c) => c.id), ['c1']);
      expect(bloc.state.error, '评论删除失败');
      expect(bloc.state.deletingIds, isEmpty);
    });
  });
}
