import 'package:belog/core/error/failures.dart';
import 'package:belog/features/messages/data/services/author_message_participant_names.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/data/models/author_profile_model.dart';
import 'package:belog/features/user/data/repositories/author_repository_impl.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthors extends Mock implements AuthorRepository {}

AuthorProfileModel _profile(String userId, String name) => AuthorProfileModel(
  userId: userId,
  displayName: name,
  followerCount: 0,
  updatedAt: DateTime.utc(2026, 11, 5),
);

void main() {
  late _MockAuthors authors;
  late AuthorMessageParticipantNames names;

  setUp(() {
    authors = _MockAuthors();
    names = AuthorMessageParticipantNames(authors);
  });

  test('resolves a name from the public author profile', () async {
    when(
      () => authors.getAuthorProfile('user-b'),
    ).thenAnswer((_) async => right(_profile('user-b', '读者乙')));

    final participant = await names.lookup('user-b');

    expect(participant?.displayName, '读者乙');
    expect(participant?.userId, 'user-b');
  });

  test('a profile with no name is not a name', () async {
    when(
      () => authors.getAuthorProfile('user-b'),
    ).thenAnswer((_) async => right(_profile('user-b', '   ')));

    final participant = await names.lookup('user-b');

    expect(participant, isNotNull);
    expect(participant?.hasName, isFalse);
  });

  test('a second lookup of the same person is served from the cache', () async {
    when(
      () => authors.getAuthorProfile('user-b'),
    ).thenAnswer((_) async => right(_profile('user-b', '读者乙')));

    await names.lookup('user-b');
    await names.lookup('user-b');

    verify(() => authors.getAuthorProfile('user-b')).called(1);
  });

  test('an offline lookup is not remembered as "no such person"', () async {
    var attempt = 0;
    when(() => authors.getAuthorProfile('user-b')).thenAnswer((_) async {
      attempt++;
      return attempt == 1
          ? left(Failure.networkOffline())
          : right(_profile('user-b', '读者乙'));
    });

    expect(await names.lookup('user-b'), isNull);
    expect((await names.lookup('user-b'))?.displayName, '读者乙');

    verify(() => authors.getAuthorProfile('user-b')).called(2);
  });

  test('a 404 is remembered, so a list does not keep asking', () async {
    when(() => authors.getAuthorProfile('ghost')).thenAnswer(
      (_) async => left(
        const Failure(
          '相关数据不存在或已被删除',
          kind: FailureKind.validation,
          code: 'server.NOT_FOUND',
        ),
      ),
    );

    expect(await names.lookup('ghost'), isNull);
    expect(await names.lookup('ghost'), isNull);

    verify(() => authors.getAuthorProfile('ghost')).called(1);
  });

  test(
    'resolve returns what it knows and only starts the budgeted lookups',
    () async {
      when(
        () => authors.getAuthorProfile(any()),
      ).thenAnswer((invocation) async {
        final userId = invocation.positionalArguments.first as String;
        return right(_profile(userId, 'name-$userId'));
      });

      final ids = [for (var i = 0; i < 20; i++) 'user-$i'];
      final resolved = await names.resolve(ids, limit: 5);

      expect(resolved, hasLength(5));
      expect(resolved['user-0']?.displayName, 'name-user-0');
      verify(() => authors.getAuthorProfile(any())).called(5);

      // A second resolve picks up where the budget stopped, no re-ask.
      final second = await names.resolve(ids, limit: 5);
      expect(second, hasLength(10));
      verify(() => authors.getAuthorProfile(any())).called(10);
    },
  );

  test('resolve dedupes ids and skips the empty one', () async {
    when(
      () => authors.getAuthorProfile('user-b'),
    ).thenAnswer((_) async => right(_profile('user-b', '读者乙')));

    final resolved = await names.resolve(['user-b', 'user-b', '']);

    expect(resolved.keys, ['user-b']);
    verify(() => authors.getAuthorProfile('user-b')).called(1);
  });

  test('resolve never returns an unknown person as if it had a name', () async {
    when(
      () => authors.getAuthorProfile(any()),
    ).thenAnswer((_) async => left(Failure.networkOffline()));

    final resolved = await names.resolve(['user-b', 'user-c']);

    expect(resolved, isEmpty);
  });

  test('the cache is capped instead of growing without a bound', () async {
    when(
      () => authors.getAuthorProfile(any()),
    ).thenAnswer((invocation) async {
      final userId = invocation.positionalArguments.first as String;
      return right(_profile(userId, 'name-$userId'));
    });

    for (var i = 0; i < AuthorMessageParticipantNames.cacheLimit + 10; i++) {
      await names.lookup('user-$i');
    }
    // The oldest entries were evicted, so asking again hits the network.
    await names.lookup('user-0');

    verify(() => authors.getAuthorProfile('user-0')).called(2);
  });

  test('the default budget matches the interface', () {
    expect(
      AuthorMessageParticipantNames(authors).lookupBudget,
      MessageParticipantNames.defaultLookupBudget,
    );
  });

  test('real author repository failures still degrade to no name', () async {
    final remote = _MockRemote();
    when(() => remote.getAuthorProfile('user-b')).thenThrow(Exception('boom'));
    final repository = AuthorRepositoryImpl(
      authorRemoteDataSource: remote,
      connectionChecker: _Connected(),
    );
    final directory = AuthorMessageParticipantNames(repository);

    expect(await directory.lookup('user-b'), isNull);
  });
}

class _MockRemote extends Mock implements AuthorRemoteDataSource {}

class _Connected implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => true;
}
