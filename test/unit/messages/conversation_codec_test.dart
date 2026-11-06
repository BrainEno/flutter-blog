import 'package:belog/features/messages/data/datasources/conversation_codec.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _message({
  String id = 'message-1',
  String conversationId = 'conversation-1',
  String senderId = 'user-b',
  String body = '你好',
  String createdAt = '2026-11-05T04:30:00.000Z',
}) => {
  'id': id,
  'conversationId': conversationId,
  'senderId': senderId,
  'body': body,
  'createdAt': createdAt,
};

Map<String, dynamic> _conversation() => {
  'id': 'conversation-1',
  'createdBy': 'user-a',
  'participantIds': ['user-a', 'user-b'],
  'createdAt': '2026-11-05T04:00:00.000Z',
  'lastActivityAt': '2026-11-05T04:30:00.000Z',
  'unreadCount': 2,
  'lastMessage': _message(),
};

void main() {
  test('reads a conversation row', () {
    final conversation = conversationFromRow(_conversation());

    expect(conversation.id, 'conversation-1');
    expect(conversation.participantIds, ['user-a', 'user-b']);
    expect(conversation.unreadCount, 2);
    expect(conversation.createdBy, 'user-a');
    expect(conversation.createdAt, DateTime.utc(2026, 11, 5, 4));
    expect(conversation.lastActivityAt, DateTime.utc(2026, 11, 5, 4, 30));
    expect(conversation.lastMessage?.body, '你好');
    expect(conversation.lastEventAt, DateTime.utc(2026, 11, 5, 4, 30));
    expect(() => conversation.participantIds.clear(), throwsUnsupportedError);
  });

  test('a new conversation may have no messages and an empty count', () {
    final conversation = conversationFromRow({
      ..._conversation(),
      'unreadCount': 0,
      'lastMessage': null,
      'lastActivityAt': null,
    });

    expect(conversation.unreadCount, 0);
    expect(conversation.lastMessage, isNull);
    expect(conversation.lastEventAt, DateTime.utc(2026, 11, 5, 4));
  });

  test('others() lists everyone but the viewer, in server order', () {
    final conversation = conversationFromRow({
      ..._conversation(),
      'participantIds': ['user-a', 'user-b', 'user-c'],
    });

    expect(conversation.others('user-a'), ['user-b', 'user-c']);
    expect(conversation.others('user-b'), ['user-a', 'user-c']);
    expect(conversation.others(null), ['user-a', 'user-b', 'user-c']);
  });

  test('reads a message row and its replay flag', () {
    final message = messageFromRow({..._message(), 'duplicate': true});

    expect(message.id, 'message-1');
    expect(message.conversationId, 'conversation-1');
    expect(message.senderId, 'user-b');
    expect(message.body, '你好');
    expect(message.createdAt, DateTime.utc(2026, 11, 5, 4, 30));
    expect(message.duplicate, isTrue);
    expect(message.sentBy('user-b'), isTrue);
    expect(message.sentBy('user-a'), isFalse);
    expect(message.sentBy(null), isFalse);
  });

  test('a row without a replay flag is a first write', () {
    expect(messageFromRow(_message()).duplicate, isFalse);
  });

  group('the envelope is strict', () {
    final cases = <String, Object?>{
      'a row that is not an object': ['conversation-1'],
      'an empty id': _conversation()..['id'] = '',
      'participants that are not a list': _conversation()
        ..['participantIds'] = 'user-a',
      'a participant that is not a string': _conversation()
        ..['participantIds'] = [1, 2],
      'a missing unread count': _conversation()..remove('unreadCount'),
      'a negative unread count': _conversation()..['unreadCount'] = -1,
      'a count that is a string': _conversation()..['unreadCount'] = '2',
      'a timestamp without an offset': _conversation()
        ..['lastActivityAt'] = '2026-11-05T04:30:00',
      'a last message that is not a row': _conversation()
        ..['lastMessage'] = 'hello',
      'a creator that is not a string': _conversation()..['createdBy'] = 42,
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(() => conversationFromRow(entry.value), throwsFormatException);
      });
    }
  });

  group('a message envelope is strict too', () {
    final cases = <String, Object?>{
      'a row that is not an object': null,
      'an empty id': _message()..['id'] = '',
      'a missing conversation': _message()..remove('conversationId'),
      'a missing sender': _message()..remove('senderId'),
      'a body that is not text': _message()..['body'] = 42,
      'a naive created time': _message()..['createdAt'] = '2026-11-05T04:30:00',
      'a missing created time': _message()..remove('createdAt'),
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(() => messageFromRow(entry.value), throwsFormatException);
      });
    }
  });

  test('an empty body is kept as-is rather than invented', () {
    final message = messageFromRow({..._message(), 'body': ''});

    expect(message.body, isEmpty);
  });

  test('a conversation without a last message still reads', () {
    final Conversation conversation = conversationFromRow({
      ..._conversation(),
      'lastMessage': null,
    });

    expect(conversation.lastMessage, isNull);
  });
}
