import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/features/blog/data/datasources/blog_local_data_source.dart';
import 'package:belog/features/blog/data/datasources/blog_remote_data_source.dart';
import 'package:belog/features/blog/data/repositories/blog_repository_impl.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Remote extends Mock implements BlogRemoteDataSource {}

class _Local extends Mock implements BlogLocalDataSource {}

class _Connection extends Mock implements ConnectionChecker {}

void main() {
  late _Remote remote;
  late _Local local;
  late _Connection connection;
  late BlogRepositoryImpl repository;

  setUp(() {
    remote = _Remote();
    local = _Local();
    connection = _Connection();
    repository = BlogRepositoryImpl(remote, local, connection);
  });

  test(
    'offline library read is local even if connectivity probing would fail',
    () async {
      final snapshot = OfflineLibrarySnapshot.empty(locale: 'zh-CN');
      when(
        () => local.inspectOfflineLibrary(),
      ).thenAnswer((_) async => snapshot);
      when(
        () => connection.isConnected,
      ).thenThrow(StateError('must not probe'));

      final result = await repository.getOfflineLibrary();

      expect(result.getRight().toNullable(), same(snapshot));
      verify(() => local.inspectOfflineLibrary()).called(1);
      verifyNever(() => connection.isConnected);
      verifyNever(() => remote.searchBlogs(any()));
    },
  );

  test(
    'offline library clear is local and maps storage failures safely',
    () async {
      when(
        () => local.clearOfflineLibrary(),
      ).thenThrow(StateError('disk full'));

      final result = await repository.clearOfflineLibrary();

      final failure = result.getLeft().toNullable();
      expect(failure?.kind, FailureKind.storage);
      expect(failure?.message, isNot(contains('disk full')));
      verify(() => local.clearOfflineLibrary()).called(1);
      verifyNever(() => connection.isConnected);
    },
  );
}
