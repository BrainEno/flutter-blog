import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/comment.dart';
import 'package:belog/features/blog/domain/entities/comment_page.dart';
import 'package:belog/features/blog/domain/usecase/comment.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_bloc.dart';
import 'package:belog/features/blog/presentation/blocs/comment/comment_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _Get extends Mock implements GetComments {}

class _Create extends Mock implements CreateComment {}

class _Delete extends Mock implements DeleteComment {}

class _Uuid extends Mock implements Uuid {}

class _Identity implements NowaveSessionIdentity {
  final events = StreamController<void>.broadcast(sync: true);
  @override
  String? activeUserId = 'a';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 1;
  @override
  Stream<void> get identityChanges => events.stream;
  void switchTo(String? id) {
    activeUserId = id;
    accessToken = id == null ? null : 'token-$id';
    sessionGeneration++;
    events.add(null);
  }
}

Comment _comment(String id, {String author = 'a'}) => Comment(
  id: id,
  articleId: 'article',
  authorId: author,
  content: 'content',
  createdAt: DateTime.utc(2026),
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _Get get;
  late _Create create;
  late _Delete delete;
  late _Uuid uuid;
  late _Identity identity;
  late CommentBloc bloc;
  var key = 0;

  setUpAll(() {
    registerFallbackValue(
      CreateCommentParams(slug: '', content: '', idempotencyKey: ''),
    );
    registerFallbackValue(const NowaveSessionFence(userId: 'a', generation: 1));
  });
  setUp(() {
    get = _Get();
    create = _Create();
    delete = _Delete();
    uuid = _Uuid();
    identity = _Identity();
    key = 0;
    when(() => uuid.v4()).thenAnswer((_) => 'key-${key++}');
    when(
      () => get('slug'),
    ).thenAnswer((_) async => right(CommentPage(items: [], nextCursor: null)));
    bloc = CommentBloc(
      getComments: get,
      createComment: create,
      deleteComment: delete,
      slug: 'slug',
      uuidGenerator: uuid,
      sessionIdentity: identity,
    );
  });
  tearDown(() async {
    await bloc.close();
    await identity.events.close();
  });

  test(
    'submit captures original fence and ignores late success after switch',
    () async {
      final gate = Completer<Either<Failure, Comment>>();
      CreateCommentParams? sent;
      when(() => create(any())).thenAnswer((invocation) {
        sent = invocation.positionalArguments.first as CreateCommentParams;
        return gate.future;
      });
      bloc.add(const CommentSubmitted(content: 'old account text'));
      await _tick();
      expect(bloc.state.submitting, isTrue);
      expect(sent!.sessionFence!.userId, 'a');
      expect(sent!.sessionFence!.generation, 1);
      identity.switchTo('b');
      await _tick();
      expect(bloc.state.submitting, isFalse);
      gate.complete(right(_comment('old')));
      await _tick();
      expect(
        bloc.state.comments.any((comment) => comment.id == 'old'),
        isFalse,
      );
      expect(bloc.state.error, isEmpty);
    },
  );

  test(
    'failed old submission never shares key with replacement account',
    () async {
      final seen = <CreateCommentParams>[];
      when(() => create(any())).thenAnswer((invocation) async {
        seen.add(invocation.positionalArguments.first as CreateCommentParams);
        return left(Failure.networkOffline());
      });
      bloc.add(const CommentSubmitted(content: 'same text'));
      await _tick();
      expect(seen.single.idempotencyKey, 'key-0');
      identity.switchTo('b');
      await _tick();
      bloc.add(const CommentSubmitted(content: 'same text'));
      await _tick();
      expect(seen.map((p) => p.idempotencyKey), ['key-0', 'key-1']);
      expect(seen.map((p) => p.sessionFence!.userId), ['a', 'b']);
    },
  );

  test('retry in the same session retains the idempotency key', () async {
    final seen = <CreateCommentParams>[];
    when(() => create(any())).thenAnswer((invocation) async {
      seen.add(invocation.positionalArguments.first as CreateCommentParams);
      return left(Failure.networkOffline());
    });
    bloc.add(const CommentSubmitted(content: 'same text'));
    await _tick();
    bloc.add(const CommentSubmitted(content: 'same text'));
    await _tick();
    expect(seen.map((p) => p.idempotencyKey), ['key-0', 'key-0']);
  });

  test('sign-out clears an in-flight delete and ignores its result', () async {
    when(() => get('slug')).thenAnswer(
      (_) async =>
          right(CommentPage(items: [_comment('one')], nextCursor: null)),
    );
    final gate = Completer<Either<Failure, void>>();
    when(
      () => delete('one', sessionFence: any(named: 'sessionFence')),
    ).thenAnswer((_) => gate.future);
    bloc.add(const CommentsRequested());
    await _tick();
    bloc.add(const CommentDeleteRequested('one'));
    await _tick();
    expect(bloc.state.deletingIds, contains('one'));
    identity.switchTo(null);
    await _tick();
    expect(bloc.state.deletingIds, isEmpty);
    gate.complete(left(Failure.networkOffline()));
    await _tick();
    expect(bloc.state.error, isEmpty);
    expect(bloc.state.comments.single.id, 'one');
  });

  test('queued old fence cannot execute after switch away and back', () async {
    final fence = bloc.captureFence()!;
    identity.switchTo('b');
    identity.switchTo('a');
    await _tick();
    bloc.add(CommentSubmitted(content: 'stale', fence: fence));
    bloc.add(CommentDeleteRequested('one', fence: fence));
    await _tick();
    verifyNever(() => create(any()));
    verifyNever(() => delete(any(), sessionFence: any(named: 'sessionFence')));
  });

  test('no active token cannot enqueue a mutation', () async {
    identity.switchTo(null);
    await _tick();
    bloc.add(const CommentSubmitted(content: 'no session'));
    bloc.add(const CommentDeleteRequested('one'));
    await _tick();
    verifyNever(() => create(any()));
    verifyNever(() => delete(any(), sessionFence: any(named: 'sessionFence')));
  });

  test(
    'a delayed list load from the old identity cannot overwrite new state',
    () async {
      final old = Completer<Either<Failure, CommentPage>>();
      var calls = 0;
      when(() => get('slug')).thenAnswer((_) {
        calls++;
        return calls == 1
            ? old.future
            : Future.value(
                right(
                  CommentPage(
                    items: [_comment('new', author: 'b')],
                    nextCursor: null,
                  ),
                ),
              );
      });
      bloc.add(const CommentsRequested());
      await _tick();
      identity.switchTo('b');
      await _tick();
      old.complete(
        right(CommentPage(items: [_comment('old')], nextCursor: null)),
      );
      await _tick();
      expect(bloc.state.comments.map((c) => c.id), ['new']);
    },
  );

  test(
    'identity invalidation rejects an event before the reset is delivered',
    () async {
      identity.switchTo('b');
      bloc.add(const CommentSubmitted(content: 'old visible composer'));
      await _tick();
      verifyNever(() => create(any()));
      expect(bloc.state.identityEpoch, 1);
    },
  );
}
