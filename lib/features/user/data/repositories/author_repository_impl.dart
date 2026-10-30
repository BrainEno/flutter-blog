import 'package:belog/core/error/exceptions.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/features/user/data/datasources/author_remote_data_source.dart';
import 'package:belog/features/user/domain/entities/author_profile.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:fpdart/fpdart.dart';

class AuthorRepositoryImpl implements AuthorRepository {
  final AuthorRemoteDataSource authorRemoteDataSource;
  final ConnectionChecker connectionChecker;

  const AuthorRepositoryImpl({
    required this.authorRemoteDataSource,
    required this.connectionChecker,
  });

  @override
  Future<Either<Failure, AuthorProfile>> getAuthorProfile(String userId) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(Failure.networkOffline());
      }

      final res = await authorRemoteDataSource.getAuthorProfile(userId);
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error(
        'getAuthorProfile failed',
        error: e,
        stackTrace: stackTrace,
      );
      return left(Failure('作者信息加载失败，请稍后重试', code: 'author.load'));
    }
  }

  @override
  Future<Either<Failure, AuthorProfile>> followAuthor(String userId) async {
    return _mutateFollow(
      () => authorRemoteDataSource.followAuthor(userId),
      offlineMessage: '无法连接到网络，关注未同步',
      offlineCode: 'follow.sync',
      logName: 'followAuthor',
    );
  }

  @override
  Future<Either<Failure, AuthorProfile>> unfollowAuthor(String userId) async {
    return _mutateFollow(
      () => authorRemoteDataSource.unfollowAuthor(userId),
      offlineMessage: '无法连接到网络，取消关注未同步',
      offlineCode: 'unfollow.sync',
      logName: 'unfollowAuthor',
    );
  }

  Future<Either<Failure, AuthorProfile>> _mutateFollow(
    Future<AuthorProfile> Function() call, {
    required String offlineMessage,
    required String offlineCode,
    required String logName,
  }) async {
    try {
      if (!await connectionChecker.isConnected) {
        return left(
          Failure(
            offlineMessage,
            kind: FailureKind.network,
            code: 'network.offline',
            l10nKey: offlineCode,
          ),
        );
      }

      final res = await call();
      return right(res);
    } on ServerException catch (e) {
      return left(e.toFailure());
    } catch (e, stackTrace) {
      AppLogger.error(logName, error: e, stackTrace: stackTrace);
      return left(Failure('关注操作失败，请稍后重试', code: 'follow.toggle'));
    }
  }
}
