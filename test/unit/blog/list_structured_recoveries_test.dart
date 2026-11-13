import 'dart:async';

import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/blog/domain/entities/structured_body_recovery.dart';
import 'package:belog/features/blog/domain/repositories/structured_recovery_catalog.dart';
import 'package:belog/features/blog/domain/usecase/list_structured_recoveries.dart';
import 'package:flutter_test/flutter_test.dart';

class _Identity implements NowaveSessionIdentity {
  @override
  String? activeUserId = 'alice';
  @override
  String? accessToken = 'token';
  @override
  int sessionGeneration = 4;
  @override
  Stream<void> get identityChanges => const Stream.empty();
}

class _Catalog implements StructuredRecoveryCatalog {
  int calls = 0;
  String? seenUser;
  int? seenCursor;
  bool fail = false;
  Completer<StructuredRecoveryIndexPage>? gate;
  StructuredRecoveryIndexPage value = StructuredRecoveryIndexPage(
    entries: [],
    nextCursor: null,
  );
  @override
  Future<StructuredRecoveryIndexPage> page({
    required String userId,
    int? afterRowId,
  }) async {
    calls++;
    seenUser = userId;
    seenCursor = afterRowId;
    if (fail) throw StateError('disk failure');
    if (gate != null) return gate!.future;
    return value;
  }
}

const _fence = NowaveSessionFence(userId: 'alice', generation: 4);
StructuredRecoveryIndexPage _page() => StructuredRecoveryIndexPage(
  entries: [
    StructuredRecoveryIndexEntry(
      rowId: 3,
      key: StructuredBodyKey(userId: 'alice', articleId: 'one', locale: 'en'),
    ),
  ],
  nextCursor: null,
);

void main() {
  late _Identity identity;
  late _Catalog catalog;
  late ListStructuredRecoveries list;
  setUp(() {
    identity = _Identity();
    catalog = _Catalog();
    list = ListStructuredRecoveries(catalog: catalog, identity: identity);
  });

  test('passes the captured user and cursor to the local catalog', () async {
    catalog.value = _page();
    final result = await list(
      fence: _fence,
      afterRowId: 2,
      isCurrent: () => true,
    );
    expect(result.status, StructuredRecoveryListStatus.ready);
    expect(result.page!.entries.single.key!.articleId, 'one');
    expect(catalog.seenUser, 'alice');
    expect(catalog.seenCursor, 2);
    expect(catalog.calls, 1);
  });

  test('empty results are valid, not a read error', () async {
    final result = await list(fence: _fence, isCurrent: () => true);
    expect(result.status, StructuredRecoveryListStatus.ready);
    expect(result.page!.entries, isEmpty);
  });

  test('storage errors do not imply that the catalog is empty', () async {
    catalog.fail = true;
    final result = await list(fence: _fence, isCurrent: () => true);
    expect(result.status, StructuredRecoveryListStatus.unavailable);
    expect(result.page, isNull);
  });

  test(
    'signed-out, mismatched, whitespace and stale identities never query',
    () async {
      for (final token in <String?>[null, '']) {
        identity.accessToken = token;
        expect(
          (await list(fence: _fence, isCurrent: () => true)).status,
          StructuredRecoveryListStatus.obsolete,
        );
      }
      identity.accessToken = 'token';
      identity.activeUserId = 'bob';
      expect(
        (await list(fence: _fence, isCurrent: () => true)).status,
        StructuredRecoveryListStatus.obsolete,
      );
      identity.activeUserId = 'alice';
      identity.sessionGeneration++;
      expect(
        (await list(fence: _fence, isCurrent: () => true)).status,
        StructuredRecoveryListStatus.obsolete,
      );
      expect(
        (await list(
          fence: const NowaveSessionFence(userId: ' alice', generation: 5),
          isCurrent: () => true,
        )).status,
        StructuredRecoveryListStatus.obsolete,
      );
      expect(catalog.calls, 0);
    },
  );

  test('same-user session replacement invalidates late result', () async {
    catalog.gate = Completer<StructuredRecoveryIndexPage>();
    final pending = list(fence: _fence, isCurrent: () => true);
    identity.sessionGeneration++;
    catalog.gate!.complete(_page());
    final result = await pending;
    expect(result.status, StructuredRecoveryListStatus.obsolete);
    expect(result.page, isNull);
  });

  test(
    'account switch and switch back still invalidate the original generation',
    () async {
      catalog.gate = Completer<StructuredRecoveryIndexPage>();
      final pending = list(fence: _fence, isCurrent: () => true);
      identity.activeUserId = 'bob';
      identity.sessionGeneration++;
      identity.activeUserId = 'alice';
      identity.sessionGeneration++;
      catalog.gate!.complete(_page());
      expect((await pending).status, StructuredRecoveryListStatus.obsolete);
    },
  );

  test('caller generation change invalidates late success and error', () async {
    var current = true;
    catalog.gate = Completer<StructuredRecoveryIndexPage>();
    final pending = list(fence: _fence, isCurrent: () => current);
    current = false;
    catalog.gate!.complete(_page());
    expect((await pending).status, StructuredRecoveryListStatus.obsolete);
    current = true;
    catalog.gate = Completer<StructuredRecoveryIndexPage>();
    final failed = list(fence: _fence, isCurrent: () => current);
    current = false;
    catalog.gate!.completeError(StateError('offline storage failure'));
    expect((await failed).status, StructuredRecoveryListStatus.obsolete);
  });

  test(
    'token refresh for the same generation does not leak or invalidate',
    () async {
      catalog.gate = Completer<StructuredRecoveryIndexPage>();
      final pending = list(fence: _fence, isCurrent: () => true);
      identity.accessToken = 'refreshed';
      catalog.gate!.complete(_page());
      expect((await pending).status, StructuredRecoveryListStatus.ready);
    },
  );

  test('malformed or cross-account catalog responses fail closed', () async {
    final bob = StructuredBodyKey(
      userId: 'bob',
      articleId: 'secret',
      locale: 'en',
    );
    final alice = StructuredBodyKey(
      userId: 'alice',
      articleId: 'safe',
      locale: 'en',
    );
    final cases = [
      StructuredRecoveryIndexPage(
        entries: [StructuredRecoveryIndexEntry(rowId: 1, key: bob)],
        nextCursor: null,
      ),
      StructuredRecoveryIndexPage(
        entries: [StructuredRecoveryIndexEntry(rowId: 0, key: alice)],
        nextCursor: null,
      ),
      StructuredRecoveryIndexPage(
        entries: [
          StructuredRecoveryIndexEntry(rowId: 3, key: alice),
          StructuredRecoveryIndexEntry(rowId: 3, key: alice),
        ],
        nextCursor: null,
      ),
      StructuredRecoveryIndexPage(
        entries: [StructuredRecoveryIndexEntry(rowId: 3, key: alice)],
        nextCursor: 9,
      ),
      StructuredRecoveryIndexPage(entries: [], nextCursor: 1),
      StructuredRecoveryIndexPage(
        entries: [
          for (var id = 1; id <= 26; id++)
            StructuredRecoveryIndexEntry(rowId: id, key: alice),
        ],
        nextCursor: null,
      ),
    ];
    for (final page in cases) {
      catalog.value = page;
      final result = await list(fence: _fence, isCurrent: () => true);
      expect(result.status, StructuredRecoveryListStatus.unavailable);
      expect(result.page, isNull);
    }
  });

  test('catalog page protects its entry collection from mutation', () {
    final original = <StructuredRecoveryIndexEntry>[];
    final page = StructuredRecoveryIndexPage(
      entries: original,
      nextCursor: null,
    );
    original.add(StructuredRecoveryIndexEntry(rowId: 1, key: null));
    expect(page.entries, isEmpty);
    expect(
      () => page.entries.add(StructuredRecoveryIndexEntry(rowId: 1, key: null)),
      throwsUnsupportedError,
    );
  });
}
