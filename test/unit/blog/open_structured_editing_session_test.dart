import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/entities/structured_edition_read.dart';
import 'package:belog/features/blog/domain/repositories/structured_body_recovery_store.dart';
import 'package:belog/features/blog/domain/repositories/structured_edition_reader.dart';
import 'package:belog/features/blog/domain/usecase/open_structured_editing_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Store extends Mock implements StructuredBodyRecoveryStore {}

class _Reader extends Mock implements StructuredEditionReader {}

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'author';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 7;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

final _key = StructuredBodyKey(
  userId: 'author',
  articleId: 'article',
  locale: 'en',
);
const _fence = NowaveSessionFence(userId: 'author', generation: 7);
const _offline = StructuredEditionReadResult.failed(
  StructuredEditionReadStatus.unavailable,
);
const _missing = StructuredEditionReadResult.failed(
  StructuredEditionReadStatus.notInAuthorWindow,
);

StructuredBodyRecovery _local() {
  final base = StructuredArticleDraft.parse(
    version: 0,
    blocks: [
      {'id': 'p', 'type': 'paragraph', 'text': 'base'},
    ],
  );
  final body = StructuredArticleDraft.parse(
    version: 0,
    blocks: [
      {'id': 'p', 'type': 'paragraph', 'text': 'unsaved local edit'},
    ],
  );
  return StructuredBodyRecovery(
    key: _key,
    backendStorageKey: 'https://api.example.invalid',
    rowId: 1,
    revision: 3,
    base: base,
    body: body,
    updatedAt: DateTime.utc(2026),
    baseStorageJson: 'base',
    bodyStorageJson: 'local',
  );
}

void main() {
  late _Store store;
  late _Reader reader;
  late _Identity identity;
  late OpenStructuredEditingSession open;
  var current = true;

  setUp(() {
    store = _Store();
    reader = _Reader();
    identity = _Identity();
    current = true;
    open = OpenStructuredEditingSession(
      reader: reader,
      store: store,
      identity: identity,
    );
    when(
      () => reader.read(key: _key, fence: _fence),
    ).thenAnswer((_) async => _missing);
    when(() => store.load(_key)).thenAnswer((_) async => null);
  });

  Future<StructuredSessionOpenResult> call() =>
      open(key: _key, fence: _fence, isCurrent: () => current);

  test(
    'local snapshot survives remote absence without any automatic write',
    () async {
      final local = _local();
      when(() => store.load(_key)).thenAnswer((_) async => local);
      final result = await call();
      expect(result.status, StructuredSessionOpenStatus.ready);
      expect(
        result.remote!.status,
        StructuredEditionReadStatus.notInAuthorWindow,
      );
      expect(result.local, same(local));
      expect(
        result.local!.body.toJsonBlocks().single['text'],
        'unsaved local edit',
      );
      verify(() => reader.read(key: _key, fence: _fence)).called(1);
      verify(() => store.load(_key)).called(1);
      verifyNoMoreInteractions(store);
    },
  );

  test('offline remote still offers the local snapshot', () async {
    final local = _local();
    when(
      () => reader.read(key: _key, fence: _fence),
    ).thenAnswer((_) async => _offline);
    when(() => store.load(_key)).thenAnswer((_) async => local);
    final result = await call();
    expect(result.status, StructuredSessionOpenStatus.ready);
    expect(result.remote!.status, StructuredEditionReadStatus.unavailable);
    expect(result.local, same(local));
    verify(() => reader.read(key: _key, fence: _fence)).called(1);
    verifyNoMoreInteractions(reader);
  });

  test('a missing local row is distinct from a failed local read', () async {
    final result = await call();
    expect(result.status, StructuredSessionOpenStatus.ready);
    expect(result.local, isNull);
    when(
      () => store.load(_key),
    ).thenThrow(const FormatException('corrupt recovery'));
    final failed = await call();
    expect(failed.status, StructuredSessionOpenStatus.localReadFailed);
    expect(
      failed.remote!.status,
      StructuredEditionReadStatus.notInAuthorWindow,
    );
    expect(failed.local, isNull);
  });

  test('storage exception does not initialize an empty recovery', () async {
    when(() => store.load(_key)).thenThrow(StateError('database unavailable'));
    final result = await call();
    expect(result.status, StructuredSessionOpenStatus.localReadFailed);
    expect(result.local, isNull);
    verify(() => store.load(_key)).called(1);
    verifyNoMoreInteractions(store);
  });

  test('session change before load makes no reads', () async {
    identity.activeUserId = 'other';
    identity.sessionGeneration++;
    expect((await call()).status, StructuredSessionOpenStatus.obsolete);
    verifyZeroInteractions(reader);
    verifyZeroInteractions(store);
  });

  test(
    'signout and same-account replacement both invalidate the fence',
    () async {
      identity.accessToken = null;
      expect((await call()).status, StructuredSessionOpenStatus.obsolete);
      identity.accessToken = 'new';
      identity.sessionGeneration++;
      expect((await call()).status, StructuredSessionOpenStatus.obsolete);
      verifyZeroInteractions(reader);
      verifyZeroInteractions(store);
    },
  );

  test('a different route owner never borrows the captured account', () async {
    final key = StructuredBodyKey(
      userId: 'another',
      articleId: 'article',
      locale: 'en',
    );
    final result = await open(key: key, fence: _fence, isCurrent: () => true);
    expect(result.status, StructuredSessionOpenStatus.obsolete);
    verifyZeroInteractions(reader);
    verifyZeroInteractions(store);
  });

  test(
    'user edit during remote read prevents applying the delayed result',
    () async {
      final pending = Completer<StructuredEditionReadResult>();
      when(
        () => reader.read(key: _key, fence: _fence),
      ).thenAnswer((_) => pending.future);
      final result = call();
      current = false;
      pending.complete(_missing);
      expect((await result).status, StructuredSessionOpenStatus.obsolete);
      verifyZeroInteractions(store);
    },
  );

  test(
    'replacement account during remote read prevents local disclosure',
    () async {
      final pending = Completer<StructuredEditionReadResult>();
      when(
        () => reader.read(key: _key, fence: _fence),
      ).thenAnswer((_) => pending.future);
      final result = call();
      identity.activeUserId = 'other';
      identity.sessionGeneration++;
      pending.complete(_offline);
      final answer = await result;
      expect(answer.status, StructuredSessionOpenStatus.obsolete);
      expect(answer.remote, isNull);
      expect(answer.local, isNull);
      verifyZeroInteractions(store);
    },
  );

  test('remote session fence failure never reads local content', () async {
    when(() => reader.read(key: _key, fence: _fence)).thenAnswer(
      (_) async => const StructuredEditionReadResult.failed(
        StructuredEditionReadStatus.sessionChanged,
      ),
    );
    final result = await call();
    expect(result.status, StructuredSessionOpenStatus.obsolete);
    verifyZeroInteractions(store);
  });

  test('user edit during local read discards both snapshots', () async {
    final pending = Completer<StructuredBodyRecovery?>();
    final started = Completer<void>();
    when(() => store.load(_key)).thenAnswer((_) {
      started.complete();
      return pending.future;
    });
    final result = call();
    await started.future;
    current = false;
    pending.complete(_local());
    final answer = await result;
    expect(answer.status, StructuredSessionOpenStatus.obsolete);
    expect(answer.remote, isNull);
    expect(answer.local, isNull);
    verify(() => store.load(_key)).called(1);
    verifyNoMoreInteractions(store);
  });

  test(
    'session replacement during local read discards both snapshots',
    () async {
      final pending = Completer<StructuredBodyRecovery?>();
      final started = Completer<void>();
      when(() => store.load(_key)).thenAnswer((_) {
        started.complete();
        return pending.future;
      });
      final result = call();
      await started.future;
      identity.sessionGeneration++;
      pending.complete(_local());
      expect((await result).status, StructuredSessionOpenStatus.obsolete);
    },
  );

  test(
    'session change during a local exception suppresses failure details',
    () async {
      final pending = Completer<StructuredBodyRecovery?>();
      final started = Completer<void>();
      when(() => store.load(_key)).thenAnswer((_) {
        started.complete();
        return pending.future;
      });
      final result = call();
      await started.future;
      identity.activeUserId = 'other';
      identity.sessionGeneration++;
      pending.completeError(const FormatException('corrupt'));
      final answer = await result;
      expect(answer.status, StructuredSessionOpenStatus.obsolete);
      expect(answer.remote, isNull);
      expect(answer.local, isNull);
    },
  );

  test('invalidated route before work does not read remote or local', () async {
    current = false;
    expect((await call()).status, StructuredSessionOpenStatus.obsolete);
    verifyZeroInteractions(reader);
    verifyZeroInteractions(store);
  });
}
