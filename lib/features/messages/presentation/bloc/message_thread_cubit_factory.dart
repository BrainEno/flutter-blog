import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:belog/features/messages/domain/services/message_participant_names.dart';
import 'package:belog/features/messages/presentation/bloc/message_thread_cubit.dart';

/// Builds the page-scoped cubit for one conversation.
///
/// The conversation id comes from the route, not from the container, so the
/// container registers how to build a thread instead of holding one.
class MessageThreadCubitFactory {
  const MessageThreadCubitFactory({
    required this.repository,
    required this.identity,
    required this.names,
  });

  final MessageRepository repository;
  final NowaveSessionIdentity identity;
  final MessageParticipantNames names;

  MessageThreadCubit create(String conversationId) => MessageThreadCubit(
    conversationId: conversationId,
    repository: repository,
    identity: identity,
    names: names,
  );
}
