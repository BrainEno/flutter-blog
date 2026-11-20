import 'dart:io';

import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/sqlite_publish_queue_store.dart';
import 'package:belog/features/blog/data/publish/publish_queue_runner.dart';
import 'package:belog/features/blog/data/publish/publish_queue_service.dart';
import 'package:belog/features/blog/domain/repositories/blog_repository.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_drainer.dart';
import 'package:belog/features/blog/domain/repositories/publish_queue_store.dart';
import 'package:belog/features/blog/presentation/blocs/publish_queue/publish_queue_cubit.dart';
import 'package:get_it/get_it.dart';

/// The publish queue (issue #23): what the server has not accepted yet.
///
/// Covers are copied into the app's own folder because a picker's temporary
/// file can be cleaned up while an entry waits for the network.
void registerPublishQueueModule(GetIt locator, DependencyContext context) {
  final sessionManager = context.sessionManager;
  locator
    ..registerLazySingleton<PublishQueueStore>(
      () => SqlitePublishQueueStore(
        context.database,
        apiBaseUrl: context.apiBaseUrl,
        directory: Directory(
          '${context.documentsDirectory.path}/publish_queue',
        ),
      ),
    )
    ..registerLazySingleton(
      () => PublishQueueRunner(
        store: locator<PublishQueueStore>(),
        repository: locator<BlogRepository>(),
        identity: sessionManager,
        connectionChecker: locator<ConnectionChecker>(),
      ),
    )
    ..registerLazySingleton(
      () => PublishQueueService(
        store: locator<PublishQueueStore>(),
        runner: locator<PublishQueueRunner>(),
        identity: sessionManager,
      ),
    )
    // The UI starts sends through the domain port, never through the data
    // layer.
    ..registerLazySingleton<PublishQueueDrainer>(
      () => locator<PublishQueueRunner>(),
    )
    ..registerFactory(
      () => PublishQueueCubit(
        store: locator<PublishQueueStore>(),
        drainer: locator<PublishQueueDrainer>(),
        identity: sessionManager,
      ),
    );
}
