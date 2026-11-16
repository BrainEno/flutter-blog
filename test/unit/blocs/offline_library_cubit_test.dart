import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/content_language.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library_query.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/usecase/offline_library.dart';
import 'package:belog/features/blog/presentation/blocs/offline_library/offline_library_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements BlogRepository {}

OfflineLibrarySnapshot _snapshot(String locale, {String id = 'story'}) =>
    OfflineLibrarySnapshot(
      locale: locale,
      summary: const OfflineLibrarySummary(articleCount: 1, estimatedBytes: 16),
      entries: [
        OfflineLibraryEntry(
          article: Blog(
            id: id,
            title: '$locale rain title',
            content: 'A local rain body.',
            posterId: 'author',
            posterName: 'Writer',
            imageUrl: '',
            tags: const ['weather'],
            updatedAt: DateTime.utc(2026),
            locale: locale,
          ),
          lastAccessedAt: DateTime.utc(2026),
          estimatedBytes: 16,
        ),
      ],
    );

void main() {
  late _Repository repository;
  late ContentLocale locale;
  late OfflineLibraryCubit cubit;

  setUp(() {
    repository = _Repository();
    locale = ContentLocale();
    cubit = OfflineLibraryCubit(
      getOfflineLibrary: GetOfflineLibrary(repository),
      clearOfflineLibrary: ClearOfflineLibrary(repository),
      contentLocale: locale,
    );
  });

  tearDown(() => cubit.close());

  test(
    'querying a loaded snapshot stays local and needs no second repository read',
    () async {
      when(
        () => repository.getOfflineLibrary(),
      ).thenAnswer((_) async => right(_snapshot('zh-CN')));

      await cubit.load();
      cubit.setQuery('rain');

      expect(cubit.state.hasValidQuery, isTrue);
      expect(cubit.state.results.single.entry.article.id, 'story');
      verify(() => repository.getOfflineLibrary()).called(1);
      verifyNever(() => repository.searchBlogs(any()));
    },
  );

  test(
    'late completion from a previous content language is never rendered',
    () async {
      final chinese = Completer<Either<Failure, OfflineLibrarySnapshot>>();
      final english = Completer<Either<Failure, OfflineLibrarySnapshot>>();
      var calls = 0;
      when(() => repository.getOfflineLibrary()).thenAnswer((_) {
        calls++;
        return calls == 1 ? chinese.future : english.future;
      });

      final first = cubit.load();
      locale.update(ContentLanguage.en);
      final second = cubit.load();
      chinese.complete(right(_snapshot('zh-CN', id: 'old')));
      await first;
      expect(cubit.state.snapshot, isNull);

      english.complete(right(_snapshot('en', id: 'new')));
      await second;
      expect(cubit.state.locale, 'en');
      expect(cubit.state.snapshot!.entries.single.article.id, 'new');
      expect(cubit.state.snapshot!.entries.single.article.locale, 'en');
    },
  );

  test(
    'a snapshot with another entry locale is treated as a storage failure',
    () async {
      final mismatched = OfflineLibrarySnapshot(
        locale: 'zh-CN',
        summary: const OfflineLibrarySummary(
          articleCount: 1,
          estimatedBytes: 16,
        ),
        entries: [_snapshot('en').entries.single],
      );
      when(
        () => repository.getOfflineLibrary(),
      ).thenAnswer((_) async => right(mismatched));

      await cubit.load();

      expect(cubit.state.snapshot, isNull);
      expect(cubit.state.loadFailure?.kind, FailureKind.storage);
    },
  );

  test(
    'clear failure preserves visible entries and presents a storage failure',
    () async {
      when(
        () => repository.getOfflineLibrary(),
      ).thenAnswer((_) async => right(_snapshot('zh-CN')));
      when(() => repository.clearOfflineLibrary()).thenAnswer(
        (_) async => left(Failure.storage(cause: StateError('disk'))),
      );

      await cubit.load();
      await cubit.clear();

      expect(cubit.state.snapshot!.entries.single.article.id, 'story');
      expect(cubit.state.clearFailure?.kind, FailureKind.storage);
      expect(cubit.state.isClearing, isFalse);
    },
  );

  test(
    'a confirmed clear does not retain rows when its verification read fails',
    () async {
      var reads = 0;
      when(() => repository.getOfflineLibrary()).thenAnswer((_) async {
        reads++;
        return reads == 1
            ? right(_snapshot('zh-CN'))
            : left(Failure.storage(cause: StateError('disk')));
      });
      when(
        () => repository.clearOfflineLibrary(),
      ).thenAnswer((_) async => right(null));

      await cubit.load();
      await cubit.clear();

      expect(cubit.state.snapshot, isNull);
      expect(cubit.state.loadFailure?.kind, FailureKind.storage);
      expect(cubit.state.isClearing, isFalse);
      expect(reads, 2);
    },
  );

  test(
    'invalid input reports validation without making a local read',
    () async {
      when(
        () => repository.getOfflineLibrary(),
      ).thenAnswer((_) async => right(_snapshot('zh-CN')));
      await cubit.load();

      cubit.setQuery('"unfinished');

      expect(cubit.state.queryIssue, OfflineLibraryQueryIssue.unclosedQuote);
      expect(cubit.state.results, isEmpty);
      verify(() => repository.getOfflineLibrary()).called(1);
    },
  );

  test('a storage failure never retains a previous locale snapshot', () async {
    locale.update(ContentLanguage.en);
    when(
      () => repository.getOfflineLibrary(),
    ).thenAnswer((_) async => left(Failure.storage(cause: StateError('disk'))));

    await cubit.load();

    expect(cubit.state.snapshot, isNull);
    expect(cubit.state.loadFailure?.kind, FailureKind.storage);
  });
}
