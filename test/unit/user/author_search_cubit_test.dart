import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/usecases/browse_authors.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:belog/features/user/presentation/bloc/author_search/author_search_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

typedef Result = Either<Failure, List<AuthorSearchResult>>;

class ScriptedRepository implements AuthorSearchRepository {
  final queries = <String>[];
  final pending = <Completer<Result>>[];
  final directoryRequests = <Completer<Result>>[];
  final searchOffsets = <int>[];
  final directoryOffsets = <int>[];

  @override
  Future<Result> search(String query, {int offset = 0}) {
    queries.add(query);
    searchOffsets.add(offset);
    final request = Completer<Result>();
    pending.add(request);
    return request.future;
  }

  @override
  Future<Result> directory({int offset = 0}) {
    directoryOffsets.add(offset);
    final request = Completer<Result>();
    directoryRequests.add(request);
    return request.future;
  }
}

AuthorSearchCubit _cubit(ScriptedRepository repository, {int? maxOffset}) =>
    AuthorSearchCubit(
      searchAuthors: SearchAuthors(repository),
      browseAuthors: BrowseAuthors(repository),
      maxOffset: maxOffset ?? maxAuthorSearchOffset,
    );

List<AuthorSearchResult> _rows(int count, {String prefix = 'a'}) =>
    List.generate(
      count,
      (index) => AuthorSearchResult(
        userId: '$prefix$index',
        followerCount: count - index,
        workCount: 1,
      ),
    );

void main() {
  test('an empty query browses the directory instead of searching', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final browse = cubit.search('   ');
    expect(repository.queries, isEmpty);
    expect(cubit.state, isA<AuthorSearchLoading>());
    repository.directoryRequests.single.complete(
      right([
        const AuthorSearchResult(
          userId: 'one',
          displayName: 'Writer',
          followerCount: 4,
          workCount: 2,
        ),
      ]),
    );
    await browse;
    final directory = cubit.state as AuthorSearchDirectory;
    expect(directory.people.single.userId, 'one');
    expect(directory.people.single.followerCount, 4);
    expect(directory.people.single.workCount, 2);
    expect(() => directory.people.clear(), throwsUnsupportedError);
    expect(repository.queries, isEmpty);
    expect(repository.directoryOffsets, [0]);
  });

  test('oversized inputs invalidate without a request', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);
    await cubit.search('🌊' * 51);
    expect(cubit.state, isA<AuthorSearchQueryTooLong>());
    expect(repository.queries, isEmpty);
    expect(repository.directoryRequests, isEmpty);
  });

  test('the directory is fetched once and reused after a search', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(
      right([const AuthorSearchResult(userId: 'cached')]),
    );
    await load;
    expect(
      (cubit.state as AuthorSearchDirectory).people.single.userId,
      'cached',
    );

    final search = cubit.search('writer');
    expect(repository.queries, ['writer']);
    cubit.queryChanged('');
    expect(
      (cubit.state as AuthorSearchDirectory).people.single.userId,
      'cached',
    );
    repository.pending.single.complete(
      right([const AuthorSearchResult(userId: 'stale')]),
    );
    await search;
    // The dropped search reply never replaces the directory the reader is
    // looking at.
    expect(
      (cubit.state as AuthorSearchDirectory).people.single.userId,
      'cached',
    );
    expect(repository.directoryRequests, hasLength(1));
  });

  test(
    'a failed directory is a failure, and clearing the field retries it',
    () async {
      final repository = ScriptedRepository();
      final cubit = _cubit(repository);
      addTearDown(cubit.close);

      final load = cubit.loadDirectory();
      repository.directoryRequests.single.complete(
        left(Failure.networkOffline(cause: 'private')),
      );
      await load;
      final failure = (cubit.state as AuthorSearchFailure).failure;
      expect(failure.code, 'network.offline');
      expect(failure.cause, isNull);

      cubit.queryChanged('');
      expect(repository.directoryRequests, hasLength(2));
      repository.directoryRequests.last.complete(
        right([const AuthorSearchResult(userId: 'retried')]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (cubit.state as AuthorSearchDirectory).people.single.userId,
        'retried',
      );
    },
  );

  test('a full page offers the next one and appends it', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    var directory = cubit.state as AuthorSearchDirectory;
    expect(directory.people, hasLength(100));
    expect(directory.nextOffset, 100);
    expect(directory.hasMore, isTrue);

    final more = cubit.loadMore();
    expect(repository.directoryOffsets, [0, 100]);
    expect(
      (cubit.state as AuthorSearchDirectory).isLoadingMore,
      isTrue,
      reason: 'the footer shows a spinner instead of a second request',
    );
    expect(cubit.state, isA<AuthorSearchDirectory>());
    cubit.loadMore();
    expect(repository.directoryOffsets, [0, 100]);

    repository.directoryRequests.last.complete(
      right([const AuthorSearchResult(userId: 'last')]),
    );
    await more;
    directory = cubit.state as AuthorSearchDirectory;
    expect(directory.people, hasLength(101));
    expect(directory.people.last.userId, 'last');
    expect(directory.nextOffset, 101);
    expect(directory.hasMore, isFalse, reason: 'a short page is the end');
  });

  test('a short first page never offers more', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(3)));
    await load;
    expect((cubit.state as AuthorSearchDirectory).hasMore, isFalse);
    await cubit.loadMore();
    expect(repository.directoryRequests, hasLength(1));
  });

  test('a shifting order does not show the same author twice', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    final more = cubit.loadMore();
    // Reach changed between the requests: a99 moved down into page two.
    repository.directoryRequests.last.complete(
      right([
        const AuthorSearchResult(userId: 'a99'),
        ..._rows(99, prefix: 'b'),
      ]),
    );
    await more;
    final directory = cubit.state as AuthorSearchDirectory;
    expect(
      directory.people.where((person) => person.userId == 'a99'),
      hasLength(1),
    );
    expect(directory.people, hasLength(199));
    expect(
      directory.nextOffset,
      200,
      reason: 'paging counts rows received, not rows kept',
    );
  });

  test('a failed next page keeps the rows and can be retried', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    final more = cubit.loadMore();
    repository.directoryRequests.last.complete(
      left(Failure.networkOffline(cause: 'private')),
    );
    await more;
    final directory = cubit.state as AuthorSearchDirectory;
    expect(directory.people, hasLength(100));
    expect(directory.isLoadingMore, isFalse);
    expect(directory.hasMore, isTrue);
    expect(directory.loadMoreFailure?.code, 'network.offline');
    expect(directory.loadMoreFailure?.cause, isNull);

    final retry = cubit.loadMore();
    expect(repository.directoryOffsets, [0, 100, 100]);
    repository.directoryRequests.last.complete(
      right([const AuthorSearchResult(userId: 'afterRetry')]),
    );
    await retry;
    final retried = cubit.state as AuthorSearchDirectory;
    expect(retried.loadMoreFailure, isNull);
    expect(retried.people.last.userId, 'afterRetry');
  });

  test('an edit invalidates a next page that is still in flight', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    final more = cubit.loadMore();
    cubit.queryChanged('writer');
    expect(cubit.state, isA<AuthorSearchLoading>());
    repository.directoryRequests.last.complete(right(_rows(100, prefix: 'b')));
    await more;
    expect(cubit.state, isA<AuthorSearchLoading>());
    expect(repository.queries, isEmpty);
  });

  test('paging stops at the API offset bound', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository, maxOffset: 200);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    for (var page = 0; page < 2; page++) {
      final more = cubit.loadMore();
      repository.directoryRequests.last.complete(
        right(_rows(100, prefix: 'p$page')),
      );
      await more;
    }
    final directory = cubit.state as AuthorSearchDirectory;
    expect(directory.nextOffset, 300);
    expect(directory.hasMore, isFalse, reason: 'beyond the API bound');
    await cubit.loadMore();
    expect(repository.directoryOffsets, [0, 100, 200]);
  });

  test('a query result pages with the same offset rule', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final search = cubit.search('writer');
    repository.pending.single.complete(right(_rows(100)));
    await search;
    expect((cubit.state as AuthorSearchSuccess).hasMore, isTrue);
    final more = cubit.loadMore();
    expect(repository.searchOffsets, [0, 100]);
    expect(repository.queries, ['writer', 'writer']);
    repository.pending.last.complete(
      right([const AuthorSearchResult(userId: 'extra')]),
    );
    await more;
    final success = cubit.state as AuthorSearchSuccess;
    expect(success.people, hasLength(101));
    expect(success.hasMore, isFalse);
  });

  test('the cached directory keeps the pages already read', () async {
    final repository = ScriptedRepository();
    final cubit = _cubit(repository);
    addTearDown(cubit.close);

    final load = cubit.loadDirectory();
    repository.directoryRequests.single.complete(right(_rows(100)));
    await load;
    final more = cubit.loadMore();
    repository.directoryRequests.last.complete(
      right([const AuthorSearchResult(userId: 'second')]),
    );
    await more;

    final search = cubit.search('writer');
    repository.pending.single.complete(right(_rows(1, prefix: 'w')));
    await search;
    cubit.queryChanged('');
    final cached = cubit.state as AuthorSearchDirectory;
    expect(cached.people, hasLength(101));
    expect(cached.nextOffset, 101);
    expect(repository.directoryRequests, hasLength(2));
  });

  test(
    'editing invalidates an older result before the next debounce fires',
    () async {
      final repository = ScriptedRepository();
      final cubit = _cubit(repository);
      addTearDown(cubit.close);
      final first = cubit.search('  old  ');
      expect(repository.queries, ['old']);
      cubit.queryChanged('new');
      repository.pending[0].complete(
        right([const AuthorSearchResult(userId: 'stale')]),
      );
      await first;
      expect(cubit.state, isA<AuthorSearchLoading>());
      final second = cubit.search('new');
      repository.pending[1].complete(
        right([const AuthorSearchResult(userId: 'new')]),
      );
      await second;
      expect((cubit.state as AuthorSearchSuccess).people.single.userId, 'new');
      expect(
        () => (cubit.state as AuthorSearchSuccess).people.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'overlapping retry, clear, errors and close discard stale replies',
    () async {
      final repository = ScriptedRepository();
      final cubit = _cubit(repository);
      final first = cubit.search('query');
      final retry = cubit.search('query');
      repository.pending[1].complete(
        left(Failure.networkOffline(cause: 'private')),
      );
      await retry;
      final failure = (cubit.state as AuthorSearchFailure).failure;
      expect(failure.code, 'network.offline');
      expect(failure.cause, isNull);
      repository.pending[0].complete(
        right([const AuthorSearchResult(userId: 'old')]),
      );
      await first;
      expect(cubit.state, isA<AuthorSearchFailure>());

      final inFlight = cubit.search('new');
      cubit.queryChanged('');
      repository.directoryRequests.single.complete(
        right([const AuthorSearchResult(userId: 'directory')]),
      );
      repository.pending[2].complete(
        right([const AuthorSearchResult(userId: 'late')]),
      );
      await inFlight;
      expect(
        (cubit.state as AuthorSearchDirectory).people.single.userId,
        'directory',
      );

      final afterClose = cubit.search('last');
      await cubit.close();
      repository.pending[3].complete(
        right([const AuthorSearchResult(userId: 'late')]),
      );
      await afterClose;
    },
  );
}
