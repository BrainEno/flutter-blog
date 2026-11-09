import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/messages/data/datasources/conversation_codec.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/conversation_message.dart';
import 'package:belog/features/messages/domain/repositories/message_repository.dart';
import 'package:fpdart/fpdart.dart';

/// The no-wave conversation API.
///
/// The fence goes to the HTTP client on every call, so a 401 cannot be replayed
/// as a different account, and private requests do not follow redirects (a
/// bearer token must not be forwarded to wherever a 3xx points). Nothing is
/// cached or logged; conversations are read from or changed on the server.
class MessageRepositoryImpl implements MessageRepository {
  const MessageRepositoryImpl(this.client);

  final NowaveApiClient client;

  /// The server accepts 1..100 conversations and 1..100 messages per page.
  static const int maxLimit = 100;

  /// `normalizeMessageWriteBody`: non-empty, trimmed, at most 20000 characters.
  static const int maxMessageLength = 20000;

  /// `normalizeConversationCreateBody`: a trimmed id of at most 300 characters.
  static const int maxUserIdLength = 300;

  @override
  Future<Either<Failure, List<Conversation>>> conversations({
    required NowaveSessionFence fence,
    int limit = 50,
  }) async {
    final bounded = _bound(limit);
    try {
      final data = await client.getJson(
        '/conversations',
        query: {'limit': '$bounded'},
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is! List || data.length > bounded) {
        throw const FormatException('Invalid conversation list');
      }
      return right(List.unmodifiable(data.map(conversationFromRow)));
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  @override
  Future<Either<Failure, Conversation>> conversation(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    try {
      final data = await client.getJson(
        '/conversations/${Uri.encodeComponent(conversationId)}',
        sessionFence: fence,
        followRedirects: false,
      );
      return right(conversationFromRow(data));
    } catch (error) {
      return left(_failureOf(error, conversationScoped: true));
    }
  }

  @override
  Future<Either<Failure, List<ConversationMessage>>> messages(
    String conversationId, {
    required NowaveSessionFence fence,
    int limit = 100,
    String? before,
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    if (before != null && before.isEmpty) {
      // An empty cursor is not a cursor: forwarding it would ask the server to
      // decode an empty id and answer 400, which looks like a client bug.
      return left(
        const Failure(
          '消息游标无效',
          kind: FailureKind.validation,
          code: 'client.parse',
        ),
      );
    }
    final bounded = _bound(limit);
    try {
      final data = await client.getJson(
        '/conversations/${Uri.encodeComponent(conversationId)}/messages',
        query: {'limit': '$bounded', if (before != null) 'before': before},
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is! List || data.length > bounded) {
        throw const FormatException('Invalid message list');
      }
      return right(List.unmodifiable(data.map(messageFromRow)));
    } catch (error) {
      return left(_failureOf(error, conversationScoped: true));
    }
  }

  @override
  Future<Either<Failure, bool>> markRead(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    try {
      final data = await client.putJson(
        '/conversations/${Uri.encodeComponent(conversationId)}/read',
        null,
        sessionFence: fence,
      );
      if (data is! bool) {
        // Anything but an explicit `true` would let the screen say "read"
        // without the server having agreed to it.
        throw const FormatException('Invalid read result');
      }
      return right(data);
    } catch (error) {
      return left(_failureOf(error, conversationScoped: true));
    }
  }

  @override
  Future<Either<Failure, bool>> deleteConversation(
    String conversationId, {
    required NowaveSessionFence fence,
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    try {
      final data = await client.deleteJson(
        '/conversations/${Uri.encodeComponent(conversationId)}',
        sessionFence: fence,
        followRedirects: false,
      );
      if (data is! bool) {
        // The route returns false when another actor already removed it; only
        // an explicit true confirms this request permanently deleted it.
        throw const FormatException('Invalid conversation deletion result');
      }
      return right(data);
    } catch (error) {
      return left(_failureOf(error, deletingConversation: true));
    }
  }

  @override
  Future<Either<Failure, Conversation>> updateParticipants(
    String conversationId, {
    required NowaveSessionFence fence,
    List<String> addUserIds = const [],
    List<String> removeUserIds = const [],
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    final removeIds = removeUserIds.toSet();
    if (_invalidParticipantIds(addUserIds) ||
        _invalidParticipantIds(removeUserIds) ||
        addUserIds.any(removeIds.contains) ||
        addUserIds.contains(fence.userId) ||
        removeUserIds.contains(fence.userId)) {
      return left(_invalidParticipantUpdate());
    }
    try {
      final data = await client.patchJson(
        '/conversations/${Uri.encodeComponent(conversationId)}/participants',
        {'addUserIds': addUserIds, 'removeUserIds': removeUserIds},
        sessionFence: fence,
        followRedirects: false,
      );
      return right(conversationFromRow(data));
    } catch (error) {
      return left(
        _failureOf(
          error,
          conversationScoped: true,
          managingParticipants: true,
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Conversation>> startConversation({
    required NowaveSessionFence fence,
    required String recipientId,
    required String idempotencyKey,
  }) async {
    if (recipientId.isEmpty ||
        recipientId.trim() != recipientId ||
        recipientId.length > maxUserIdLength) {
      return left(
        const Failure(
          '收件人标识无效',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    if (recipientId == fence.userId) {
      // Talking to yourself is not a private message; refusing here keeps the
      // server from having to answer a nonsensical conversation.
      return left(
        const Failure(
          '不能给自己发私信',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    if (idempotencyKey.isEmpty) {
      return left(
        const Failure(
          '缺少幂等键，无法安全创建会话',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    try {
      final data = await client.postJson(
        '/conversations',
        {
          'participantIds': [recipientId],
        },
        extraHeaders: {'Idempotency-Key': idempotencyKey},
        sessionFence: fence,
      );
      return right(conversationFromRow(data));
    } catch (error) {
      return left(_failureOf(error));
    }
  }

  @override
  Future<Either<Failure, ConversationMessage>> sendMessage(
    String conversationId, {
    required NowaveSessionFence fence,
    required String body,
    required String idempotencyKey,
  }) async {
    final invalid = _invalidConversationId(conversationId);
    if (invalid != null) return left(invalid);
    if (body.isEmpty || body.trim() != body || body.length > maxMessageLength) {
      return left(
        const Failure(
          '消息不能为空，最多 20000 字，首尾不能有空白',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    if (idempotencyKey.isEmpty) {
      return left(
        const Failure(
          '缺少幂等键，无法安全发送',
          kind: FailureKind.validation,
          code: 'messages.invalid',
        ),
      );
    }
    try {
      final data = await client.postJson(
        '/conversations/${Uri.encodeComponent(conversationId)}/messages',
        {'body': body},
        extraHeaders: {'Idempotency-Key': idempotencyKey},
        sessionFence: fence,
      );
      return right(messageFromRow(data));
    } catch (error) {
      return left(_failureOf(error, conversationScoped: true));
    }
  }

  int _bound(int limit) {
    if (limit < 1) return 1;
    if (limit > maxLimit) return maxLimit;
    return limit;
  }

  Failure? _invalidConversationId(String id) {
    if (id.isEmpty || id.trim() != id || id.length > maxUserIdLength) {
      return const Failure(
        '会话标识无效',
        kind: FailureKind.validation,
        code: 'client.parse',
      );
    }
    return null;
  }

  bool _invalidParticipantIds(List<String> ids) {
    if (ids.length > 20) return true;
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || id.trim() != id || id.length > maxUserIdLength) {
        return true;
      }
      if (!seen.add(id)) return true;
    }
    return false;
  }

  Failure _invalidParticipantUpdate() => const Failure(
    'Invalid participant update.',
    kind: FailureKind.validation,
    code: 'messages.participantsInvalid',
  );

  /// Maps a failure to the one message the reader needs.
  ///
  /// [conversationScoped] separates "this conversation is not yours" (404 on a
  /// conversation endpoint, which the server also uses for "no such
  /// conversation") from "this deployment has no conversations at all" (404 on
  /// the collection endpoints).
  Failure _failureOf(
    Object error, {
    bool conversationScoped = false,
    bool deletingConversation = false,
    bool managingParticipants = false,
  }) {
    if (error is NowaveApiException) {
      if (error.code == 'SESSION_CHANGED') {
        // The account moved under this request. That is the caller's fence to
        // interpret, not a conversation state; the shared mapper words it.
        return mapErrorToFailure(error).forPresentation();
      }
      if (error.code == 'IDEMPOTENCY_CONFLICT') {
        // The same key was used for a different request. Distinct from a plain
        // state conflict: the retry is what has to change.
        return const Failure(
          '重复提交的内容不一致，请刷新后重试',
          kind: FailureKind.validation,
          code: 'server.IDEMPOTENCY_CONFLICT',
        );
      }
      if (error.statusCode == 403) {
        if (deletingConversation) {
          return const Failure(
            '只有会话创建者可以删除这个会话',
            kind: FailureKind.permission,
            code: 'messages.deleteForbidden',
          );
        }
        if (managingParticipants) {
          return const Failure(
            'Participant management is restricted to the conversation creator.',
            kind: FailureKind.permission,
            code: 'messages.participantsForbidden',
          );
        }
        return const Failure(
          '你没有权限查看这个会话',
          kind: FailureKind.permission,
          code: 'messages.forbidden',
        );
      }
      if (error.statusCode == 404) {
        if (deletingConversation) {
          // The current API returns data:false for a missing conversation, so
          // an HTTP 404 on DELETE means this deployment lacks the route.
          return const Failure(
            '此服务器暂不支持删除会话',
            kind: FailureKind.server,
            code: 'messages.deleteUnavailable',
          );
        }
        if (managingParticipants) {
          return const Failure(
            'The conversation is missing or this server does not support participant management.',
            kind: FailureKind.server,
            code: 'messages.participantsUnavailable',
          );
        }
        return conversationScoped
            ? const Failure(
                '会话不存在，或你不属于这个会话',
                kind: FailureKind.validation,
                code: 'messages.missing',
              )
            : const Failure(
                '此服务器暂不提供私信',
                kind: FailureKind.server,
                code: 'messages.unavailable',
              );
      }
      if (error.statusCode == 405) {
        // The method/route shape is not supported: an older deployment, not a
        // missing conversation.
        if (deletingConversation) {
          return const Failure(
            '此服务器暂不支持删除会话',
            kind: FailureKind.server,
            code: 'messages.deleteUnavailable',
          );
        }
        if (managingParticipants) {
          return const Failure(
            'This server does not support participant management.',
            kind: FailureKind.server,
            code: 'messages.participantsUnavailable',
          );
        }
        return const Failure(
          '此服务器暂不提供私信',
          kind: FailureKind.server,
          code: 'messages.unavailable',
        );
      }
      if (error.statusCode == 401) {
        return const Failure(
          '登录已过期，请重新登录',
          kind: FailureKind.auth,
          code: 'server.UNAUTHENTICATED',
        );
      }
      if (error.statusCode == 409) {
        return managingParticipants
            ? const Failure(
                'The conversation changed. Refresh and try again.',
                kind: FailureKind.validation,
                code: 'messages.participantsConflict',
              )
            : const Failure(
                '该操作与当前会话状态冲突，请刷新后重试',
                kind: FailureKind.validation,
                code: 'server.CONFLICT',
              );
      }
      if (error.statusCode == 400) {
        return managingParticipants
            ? _invalidParticipantUpdate()
            : const Failure(
                '会话内容不符合要求，请检查后重试',
                kind: FailureKind.validation,
                code: 'messages.invalid',
              );
      }
      if (error.statusCode == 429) {
        return const Failure(
          '操作过于频繁，请稍后再试',
          kind: FailureKind.server,
          code: 'server.RATE_LIMITED',
        );
      }
      // The shared client reports a malformed success envelope as HTTP_200.
      if (error.statusCode >= 200 && error.statusCode < 300) {
        return _parseFailure();
      }
    }
    if (error is FormatException) return _parseFailure();
    // The mapper classifies network, timeout, auth, server and parse failures.
    return mapErrorToFailure(error).forPresentation();
  }

  Failure _parseFailure() => const Failure(
    '私信数据格式错误，请更新应用后重试',
    kind: FailureKind.validation,
    code: 'client.parse',
  );
}
