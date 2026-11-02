import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:belog/features/user/domain/repositories/author_search_repository.dart';
import 'package:belog/features/user/domain/usecases/search_authors.dart';
import 'package:belog/features/user/presentation/bloc/author_search/author_search_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

typedef Result = Either<Failure, List<AuthorSearchResult>>;

class ScriptedRepository implements AuthorSearchRepository {
  final queries = <String>[];
  final pending = <Completer<Result>>[];

  @override
  Future<Result> search(String query) {
    queries.add(query);
    final request = Completer<Result>();
    pending.add(request);
    return request.future;
  }
}

void main() {
  test('empty and oversized inputs invalidate without a request', () async {
    final repository = ScriptedRepository();
    final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
    addTearDown(cubit.close);
    await cubit.search('  ');
    expect(cubit.state, isA<AuthorSearchInitial>());
    await cubit.search('🌊' * 51);
    expect(cubit.state, isA<AuthorSearchQueryTooLong>());
    expect(repository.queries, isEmpty);
  });

  test(
    'editing invalidates an older result before the next debounce fires',
    () async {
      final repository = ScriptedRepository();
      final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
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
      final cubit = AuthorSearchCubit(searchAuthors: SearchAuthors(repository));
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
      repository.pending[2].complete(
        right([const AuthorSearchResult(userId: 'late')]),
      );
      await inFlight;
      expect(cubit.state, isA<AuthorSearchInitial>());

      final afterClose = cubit.search('last');
      await cubit.close();
      repository.pending[3].complete(
        right([const AuthorSearchResult(userId: 'late')]),
      );
      await afterClose;
    },
  );
}
