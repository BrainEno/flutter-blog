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

  @override
  Future<Result> search(String query) {
    queries.add(query);
    final request = Completer<Result>();
    pending.add(request);
    return request.future;
  }

  @override
  Future<Result> directory() {
    final request = Completer<Result>();
    directoryRequests.add(request);
    return request.future;
  }
}

AuthorSearchCubit _cubit(ScriptedRepository repository) => AuthorSearchCubit(
  searchAuthors: SearchAuthors(repository),
  browseAuthors: BrowseAuthors(repository),
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
