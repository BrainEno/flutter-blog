import 'dart:convert';

import 'package:belog/features/notifications/domain/entities/app_notification.dart';

/// Parses one serialized `me.notifications` row.
///
/// The server sends `payload` as a JSON *string* (a stored projection of the
/// event, not a nested object), so it is decoded here and never rendered raw.
/// A row that breaks the *envelope* contract (id, payload kind, timestamps)
/// throws [FormatException]. A payload this build cannot name - a new event
/// type, a deletion or message without its key field, or text that is not JSON
/// is not an error: it becomes [AppNotificationKind.unknown] and is still listed, because
/// "something happened" is true even when its details are not understood yet.
AppNotification notificationFromRow(Object? row) {
  if (row is! Map<String, dynamic>) {
    throw const FormatException('Invalid notification row');
  }
  final id = row['id'];
  final eventKey = row['eventKey'];
  final payload = row['payload'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid notification id');
  }
  if (eventKey is! String) {
    throw const FormatException('Invalid notification event key');
  }
  if (payload is! String) {
    throw const FormatException('Invalid notification payload');
  }
  final decoded = _decodePayload(payload);
  return AppNotification(
    id: id,
    eventKey: eventKey,
    kind: decoded.kind,
    createdAt: _requiredTime(row['createdAt']),
    readAt: _readTime(row['readAt']),
    articleId: decoded.articleId,
    purgesAt: decoded.purgesAt,
    conversationId: decoded.conversationId,
    articleSlug: decoded.articleSlug,
    articleLocale: decoded.articleLocale,
    followerId: decoded.followerId,
  );
}

/// The understood part of a payload.
class _DecodedPayload {
  const _DecodedPayload(
    this.kind, {
    this.articleId,
    this.purgesAt,
    this.conversationId,
    this.articleSlug,
    this.articleLocale,
    this.followerId,
  });

  final AppNotificationKind kind;
  final String? articleId;
  final DateTime? purgesAt;
  final String? conversationId;
  final String? articleSlug;
  final NotificationArticleLocale? articleLocale;
  final String? followerId;
}

const _unknownPayload = _DecodedPayload(AppNotificationKind.unknown);

_DecodedPayload _decodePayload(String raw) {
  Object? value;
  try {
    value = jsonDecode(raw);
  } on FormatException {
    return _unknownPayload;
  }
  if (value is! Map<String, dynamic>) return _unknownPayload;
  switch (value['type']) {
    // These producers describe the recipient's event. Historical rows may
    // lack routing fields; never use an unvalidated payload as a URL.
    case 'article.commented':
      return _DecodedPayload(
        AppNotificationKind.articleCommented,
        articleSlug: AppNotification.validArticleSlug(value['slug']),
        articleLocale: _articleLocale(value['locale']),
      );
    case 'article.comment_replied':
      return _DecodedPayload(
        AppNotificationKind.commentReplied,
        articleSlug: AppNotification.validArticleSlug(value['slug']),
        articleLocale: _articleLocale(value['locale']),
      );
    case 'article.liked':
      return _DecodedPayload(
        AppNotificationKind.articleLiked,
        articleSlug: AppNotification.validArticleSlug(value['slug']),
        articleLocale: _articleLocale(value['locale']),
      );
    case 'user.followed':
      return _DecodedPayload(
        AppNotificationKind.userFollowed,
        followerId: AppNotification.validFollowerId(value['followerId']),
      );
    case 'article.deleted':
      final articleId = value['articleId'];
      if (articleId is! String || articleId.isEmpty) return _unknownPayload;
      return _DecodedPayload(
        AppNotificationKind.articleDeleted,
        articleId: articleId,
        purgesAt: _optionalTime(value['purgesAt']),
      );
    case 'message.created':
      final conversationId = value['conversationId'];
      if (conversationId is! String || conversationId.isEmpty) {
        return _unknownPayload;
      }
      return _DecodedPayload(
        AppNotificationKind.messageReceived,
        conversationId: conversationId,
      );
  }
  return _unknownPayload;
}

// Only explicit, supported producer values are retained; never render raw payload.
NotificationArticleLocale? _articleLocale(Object? value) => switch (value) {
  'en' => NotificationArticleLocale.english,
  'zh-CN' => NotificationArticleLocale.simplifiedChinese,
  'zh-TW' => NotificationArticleLocale.traditionalChinese,
  _ => null,
};

/// no-wave serializes instants with an offset (normally `Z`). A zone-less value
/// is rejected instead of being read as this device's local time.
final RegExp _timeZone = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$');

DateTime _requiredTime(Object? value) {
  final parsed = value is String && _timeZone.hasMatch(value)
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null) {
    throw const FormatException('Invalid notification time');
  }
  return parsed;
}

DateTime? _readTime(Object? value) {
  if (value == null) return null;
  return _requiredTime(value);
}

DateTime? _optionalTime(Object? value) {
  if (value == null) return null;
  final parsed = value is String && _timeZone.hasMatch(value)
      ? DateTime.tryParse(value)
      : null;
  return parsed;
}
