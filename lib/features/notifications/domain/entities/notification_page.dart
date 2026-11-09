import 'package:belog/features/notifications/domain/entities/app_notification.dart';

/// One slice of the notification inbox.
///
/// The REST API returns a plain array rather than paging metadata. The
/// repository builds [nextCursor] from the last row in this response; it is an
/// opaque continuation token for the next request, and is null for an empty
/// response.
class NotificationPage {
  const NotificationPage({required this.items, required this.nextCursor});

  final List<AppNotification> items;
  final String? nextCursor;
}
