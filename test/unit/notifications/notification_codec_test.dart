import 'dart:convert';

import 'package:belog/features/notifications/data/datasources/notification_codec.dart';
import 'package:belog/features/notifications/domain/entities/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String id = 'notification-1',
  String eventKey = 'message.created:message-1:user-a',
  Object? payload = const {
    'type': 'message.created',
    'messageId': 'message-1',
    'conversationId': 'conversation-1',
    'senderId': 'user-b',
  },
  String createdAt = '2026-11-05T04:30:00.000Z',
  String? readAt,
}) => {
  'id': id,
  'eventKey': eventKey,
  'payload': payload is String ? payload : jsonEncode(payload),
  'createdAt': createdAt,
  'readAt': readAt,
};

void main() {
  test('understands a message notification and keeps the conversation id', () {
    final notification = notificationFromRow(_row());

    expect(notification.id, 'notification-1');
    expect(notification.kind, AppNotificationKind.messageReceived);
    expect(notification.conversationId, 'conversation-1');
    expect(notification.articleId, isNull);
    expect(notification.createdAt, DateTime.utc(2026, 11, 5, 4, 30));
    expect(notification.isRead, isFalse);
    expect(notification.readAt, isNull);
    // The payload carries the sender id; nothing from it is exposed as data.
    expect(notification.toString(), isNot(contains('user-b')));
    expect(notification.toString(), isNot(contains('message-1')));
  });

  test('understands an article deletion and its purge date', () {
    final notification = notificationFromRow(
      _row(
        eventKey: 'article.deleted:article-9:user-a',
        payload: const {
          'type': 'article.deleted',
          'articleId': 'article-9',
          'purgesAt': '2026-12-05T00:00:00.000Z',
        },
      ),
    );

    expect(notification.kind, AppNotificationKind.articleDeleted);
    expect(notification.articleId, 'article-9');
    expect(notification.purgesAt, DateTime.utc(2026, 12, 5));
    expect(notification.conversationId, isNull);
  });

  test('an article deletion without a purge date is still understood', () {
    final notification = notificationFromRow(
      _row(
        payload: const {
          'type': 'article.deleted',
          'articleId': 'article-9',
        },
      ),
    );

    expect(notification.kind, AppNotificationKind.articleDeleted);
    expect(notification.articleId, 'article-9');
    expect(notification.purgesAt, isNull);
  });

  test('a read notification keeps its first read time', () {
    final readAt = DateTime.utc(2026, 11, 5, 6);
    final notification = notificationFromRow(
      _row(readAt: '2026-11-05T06:00:00.000Z'),
    );

    expect(notification.isRead, isTrue);
    expect(notification.readAt, readAt);
    // Marking again must not move the timestamp the server recorded first.
    expect(notification.markedRead(DateTime.utc(2026, 11, 6)).readAt, readAt);
  });

  group('a payload this build cannot name is listed, not dropped', () {
    for (final entry in <String, String>{
      'an unknown event type': '{"type":"comment.replied","commentId":"c-1"}',
      'no type at all': '{"messageId":"m-1"}',
      'text that is not JSON': 'not json at all',
      'JSON that is not an object': '[1,2,3]',
      'a message without a conversation': '{"type":"message.created"}',
      'a deletion without an article': '{"type":"article.deleted"}',
    }.entries) {
      test(entry.key, () {
        final notification = notificationFromRow(_row(payload: entry.value));

        expect(notification.kind, AppNotificationKind.unknown);
        expect(notification.isRead, isFalse);
        expect(notification.conversationId, isNull);
        expect(notification.articleId, isNull);
        expect(notification.createdAt, DateTime.utc(2026, 11, 5, 4, 30));
      });
    }
  });

  group('a broken envelope is rejected', () {
    final broken = <String, Object?>{
      'not a map': 'notification',
      'no id': _row()..remove('id'),
      'an empty id': _row(id: ''),
      'no event key': _row()..remove('eventKey'),
      'a non-string event key': _row()..['eventKey'] = 7,
      'no payload': _row()..remove('payload'),
      'a nested payload object': {
        ..._row(),
        'payload': const {'type': 'message.created'},
      },
      'no created time': _row()..remove('createdAt'),
      'a zone-less created time': _row(createdAt: '2026-11-05T04:30:00'),
      'a non-string created time': _row()..['createdAt'] = 1730000000,
      'a non-string read time': _row()..['readAt'] = 1730000000,
      'a zone-less read time': _row(readAt: '2026-11-05T06:00:00'),
    };

    for (final entry in broken.entries) {
      test(entry.key, () {
        expect(
          () => notificationFromRow(entry.value),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  test('an explicit offset is accepted and stays the same instant', () {
    final notification = notificationFromRow(
      _row(createdAt: '2026-11-05T12:30:00+08:00'),
    );

    expect(notification.createdAt, DateTime.utc(2026, 11, 5, 4, 30));
    expect(notification.createdAt.isUtc, isTrue);
  });
}
