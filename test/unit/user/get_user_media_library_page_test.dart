import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:belog/features/user/domain/repositories/user_repository.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserRepository extends Mock implements UserRepository {}

void main() {
  const fence = NowaveSessionFence(userId: 'user-a', generation: 7);
  late _MockUserRepository repository;
  late GetUserMediaLibraryPage useCase;

  setUp(() {
    repository = _MockUserRepository();
    useCase = GetUserMediaLibraryPage(repository);
  });

  test('forwards the session fence and opaque cursor unchanged', () async {
    final page = UserMediaPage(items: const [], nextCursor: 'next');
    when(
      () => repository.getMediaLibraryPage(
        sessionFence: fence,
        cursor: 'opaque/next+cursor',
      ),
    ).thenAnswer((_) async => right(page));

    final result = await useCase(
      const GetUserMediaLibraryPageParams(
        sessionFence: fence,
        cursor: 'opaque/next+cursor',
      ),
    );

    expect(result.getRight().toNullable(), same(page));
    verify(
      () => repository.getMediaLibraryPage(
        sessionFence: fence,
        cursor: 'opaque/next+cursor',
      ),
    ).called(1);
  });

  test('returns repository failures unchanged', () async {
    final failure = Failure.networkOffline();
    when(
      () => repository.getMediaLibraryPage(sessionFence: fence, cursor: null),
    ).thenAnswer((_) async => left(failure));

    final result = await useCase(
      const GetUserMediaLibraryPageParams(sessionFence: fence),
    );

    expect(result.getLeft().toNullable(), same(failure));
  });
}
