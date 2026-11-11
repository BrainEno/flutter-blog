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

  group(
    'recognizes notification producer types without exposing payload details',
    () {
      final cases = <String, AppNotificationKind>{
        'article.commented': AppNotificationKind.articleCommented,
        'article.comment_replied': AppNotificationKind.commentReplied,
        'article.liked': AppNotificationKind.articleLiked,
        'user.followed': AppNotificationKind.userFollowed,
      };
      for (final entry in cases.entries) {
        test(entry.key, () {
          for (final payload in [
            {'type': entry.key},
            {
              'type': entry.key,
              'slug': 'work',
              'articleId': 'article',
              'commentId': 'comment',
              'followerId': 'follower',
              'url': 'https://example.invalid/private',
            },
          ]) {
            final notice = notificationFromRow(_row(payload: payload));
            expect(notice.kind, entry.value);
            expect(notice.articleId, isNull);
            expect(notice.conversationId, isNull);
            expect(notice.purgesAt, isNull);
            expect(
              notice.markedRead(DateTime.utc(2026, 11, 6)).kind,
              entry.value,
            );
          }
        });
      }
    },
  );

  group('safe optional local destinations', () {
    for (final type in [
      'article.commented',
      'article.comment_replied',
      'article.liked',
    ]) {
      test(
        '$type validates work addresses and preserves them after marking',
        () {
          final notice = notificationFromRow(
            _row(
              payload: {
                'type': type,
                'slug': 'work-123',
                'url': 'https://evil.invalid',
              },
            ),
          );
          expect(notice.articleTarget, 'work-123');
          expect(
            notice.markedRead(DateTime.utc(2026)).articleTarget,
            'work-123',
          );
          for (final invalid in [
            null,
            '',
            'bad/route',
            '../x',
            'https://evil.invalid',
            'bad?x=1',
            'bad\n',
            'Upper',
            'a--b',
            'a' * 161,
            4,
          ]) {
            final bad = notificationFromRow(
              _row(payload: {'type': type, 'slug': invalid}),
            );
            expect(bad.articleTarget, isNull);
            expect(bad.kind, notice.kind);
          }
          expect(
            notificationFromRow(
              _row(payload: {'type': type, 'slug': 'a' * 160}),
            ).articleTarget,
            'a' * 160,
          );
        },
      );
    }
    test('conversation destinations use the bounded local route subset', () {
      for (final id in ['conversation-1', 'UUID_A-z09', 'x' * 300]) {
        final notice = notificationFromRow(
          _row(payload: {'type': 'message.created', 'conversationId': id}),
        );
        expect(notice.kind, AppNotificationKind.messageReceived);
        expect(notice.conversationTarget, id);
        expect(notice.markedRead(DateTime.utc(2026)).conversationTarget, id);
      }
      for (final invalid in [
        '../x',
        'a/b',
        'https://bad.invalid',
        'a?x=1',
        'a#b',
        'bad\n',
        '%2f',
        ' a',
        'a ',
        'x' * 301,
      ]) {
        final notice = notificationFromRow(
          _row(payload: {'type': 'message.created', 'conversationId': invalid}),
        );
        expect(notice.kind, AppNotificationKind.messageReceived);
        expect(notice.conversationId, isNull);
        expect(notice.conversationTarget, isNull);
      }
      for (final missing in [null, '', 3]) {
        final notice = notificationFromRow(
          _row(payload: {'type': 'message.created', 'conversationId': missing}),
        );
        expect(notice.kind, AppNotificationKind.unknown);
        expect(notice.conversationTarget, isNull);
      }
      final manual = AppNotification(
        id: 'id',
        eventKey: '',
        kind: AppNotificationKind.messageReceived,
        createdAt: DateTime.utc(2026),
        readAt: null,
        conversationId: '../bad',
      );
      expect(manual.conversationTarget, isNull);
      final wrongType = AppNotification(
        id: 'id',
        eventKey: '',
        kind: AppNotificationKind.articleLiked,
        createdAt: DateTime.utc(2026),
        readAt: null,
        conversationId: 'valid-id',
      );
      expect(wrongType.conversationTarget, isNull);
    });
    test(
      'follower identifier is bounded, safe and preserved after marking',
      () {
        final notice = notificationFromRow(
          _row(
            payload: {'type': 'user.followed', 'followerId': 'user_123-ABC'},
          ),
        );
        expect(notice.followerTarget, 'user_123-ABC');
        expect(
          notice.markedRead(DateTime.utc(2026)).followerTarget,
          'user_123-ABC',
        );
        for (final invalid in [
          null,
          '',
          '../user',
          'user/other',
          'https://evil.invalid',
          'user?x',
          'user\n',
          'x' * 301,
          3,
        ]) {
          final bad = notificationFromRow(
            _row(payload: {'type': 'user.followed', 'followerId': invalid}),
          );
          expect(bad.kind, AppNotificationKind.userFollowed);
          expect(bad.followerTarget, isNull);
        }
        expect(
          notificationFromRow(
            _row(payload: {'type': 'user.followed', 'followerId': 'x' * 300}),
          ).followerTarget,
          'x' * 300,
        );
      },
    );
    test('unrelated types never acquire destinations', () {
      final unknown = notificationFromRow(
        _row(payload: {'type': 'future', 'slug': 'good', 'followerId': 'good'}),
      );
      expect(unknown.articleTarget, isNull);
      expect(unknown.followerTarget, isNull);
    });
  });

  test('article source locale is allowlisted and survives marking read', () {
    final languages = <String, NotificationArticleLocale>{
      'en': NotificationArticleLocale.english,
      'zh-CN': NotificationArticleLocale.simplifiedChinese,
      'zh-TW': NotificationArticleLocale.traditionalChinese,
    };
    for (final type in [
      'article.commented',
      'article.comment_replied',
      'article.liked',
    ]) {
      for (final entry in languages.entries) {
        final notice = notificationFromRow(
          _row(payload: {'type': type, 'slug': 'work-1', 'locale': entry.key}),
        );
        expect(notice.articleSourceLocale, entry.value);
        expect(
          notice.markedRead(DateTime.utc(2026)).articleSourceLocale,
          entry.value,
        );
      }
      for (final value in [
        null,
        '',
        'en-US',
        'zh',
        '../en',
        1,
        ['en'],
      ]) {
        expect(
          notificationFromRow(
            _row(payload: {'type': type, 'slug': 'work-1', 'locale': value}),
          ).articleSourceLocale,
          isNull,
        );
      }
      expect(
        notificationFromRow(
          _row(payload: {'type': type, 'slug': '../bad', 'locale': 'en'}),
        ).articleSourceLocale,
        isNull,
      );
    }
    expect(
      notificationFromRow(
        _row(
          payload: {'type': 'user.followed', 'slug': 'work-1', 'locale': 'en'},
        ),
      ).articleSourceLocale,
      isNull,
    );
  });

  test('an article deletion without a purge date is still understood', () {
    final notification = notificationFromRow(
      _row(
        payload: const {'type': 'article.deleted', 'articleId': 'article-9'},
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
