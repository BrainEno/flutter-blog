import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/messages/data/repositories/message_repository_impl.dart';
import 'package:belog/features/messages/data/services/author_message_participant_names.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/messages/presentation/bloc/message_inbox_cubit.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit_factory.dart';
import 'package:belog/features/messages/presentation/bloc/message_unread_badge_cubit.dart';
import 'package:belog/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:belog/features/notifications/domain/repositories/notification_repository.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_badge_cubit.dart';
import 'package:belog/features/notifications/presentation/bloc/notification_inbox_cubit.dart';
import 'package:belog/features/user/domain/repositories/author_repository.dart';
import 'package:get_it/get_it.dart';

/// Notifications and private messages. Both are read when a screen opens and
/// never polled; every cubit is fenced to the account that opened it.
void registerInboxModule(GetIt locator, DependencyContext context) {
  final apiClient = context.apiClient;
  final sessionManager = context.sessionManager;
  locator
    // The notification inbox (#23 follow-up): read on open, never polled.
    ..registerFactory<NotificationRepository>(
      () => NotificationRepositoryImpl(apiClient),
    )
    ..registerFactory(
      () => NotificationInboxCubit(
        repository: locator<NotificationRepository>(),
        identity: sessionManager,
      ),
    )
    // The profile menu badge: one number, read when the screen opens.
    ..registerFactory(
      () => NotificationBadgeCubit(
        repository: locator<NotificationRepository>(),
        identity: sessionManager,
      ),
    )
    // Private conversations (#198 follow-up): read on open, never polled.
    ..registerFactory<MessageRepository>(() => MessageRepositoryImpl(apiClient))
    ..registerFactory(
      () => MessageUnreadBadgeCubit(
        repository: locator<MessageRepository>(),
        identity: sessionManager,
      ),
    )
    // Conversation ids are the only identities the API sends, so names come
    // from the public author profile - bounded per screen, cached across
    // sessions because they are public data either way.
    ..registerLazySingleton<MessageParticipantNames>(
      () => AuthorMessageParticipantNames(locator<AuthorRepository>()),
    )
    ..registerFactory(
      () => MessageInboxCubit(
        repository: locator<MessageRepository>(),
        identity: sessionManager,
        names: locator<MessageParticipantNames>(),
      ),
    )
    // A conversation id comes from the route, so the container registers how
    // to build a thread rather than one thread.
    ..registerFactory(
      () => MessageThreadCubitFactory(
        repository: locator<MessageRepository>(),
        identity: sessionManager,
        names: locator<MessageParticipantNames>(),
      ),
    );
}
