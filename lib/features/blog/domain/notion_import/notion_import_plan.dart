import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/config/app_limits.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/blog/domain/notion_import/notion_import.dart';

/// An opaque, short-lived server preview bound to one exact local snapshot.
///
/// Only the server can authenticate the token and enforce its actor, database,
/// source hash and target revisions. This client validates transport shape and
/// prevents accidental cross-session or cross-selection reuse; neither check
/// authenticates a server. The token is sensitive, not encrypted, and must not
/// be displayed, persisted, copied to diagnostics, decoded or logged.
final class NotionImportPlan {
  NotionImportPlan._({
    required this.bundle,
    required this.fence,
    required this.expiresAt,
    required this.localDeadline,
    required String token,
  }) : _token = token;

  /// The no-wave limit is 512 KiB. Its current token is ASCII base64url, so
  /// UTF-16 length and byte length agree for every value the shape accepts.
  static const maxTokenBytes = AppLimits.notionImportPlanMaxTokenBytes;
  static const localLifetime = AppDurations.notionImportPlanLifetime;
  static final _shape = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$');
  static final _isoUtc = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );

  final NotionBundle bundle;
  final NowaveSessionFence fence;
  final DateTime expiresAt;
  final DateTime localDeadline;
  String? _token;

  /// Refuses old or malformed server responses rather than offering an
  /// unprotected apply. Do not infer token authenticity from this parser.
  factory NotionImportPlan.fromPreview({
    required NotionBundle bundle,
    required NowaveSessionFence fence,
    required Object? token,
    required Object? expiresAt,
    DateTime? now,
  }) {
    if (fence.userId.isEmpty ||
        token is! String ||
        token.length > maxTokenBytes ||
        !_shape.hasMatch(token) ||
        expiresAt is! String ||
        !_isoUtc.hasMatch(expiresAt)) {
      throw const NotionImportPlanFormatException();
    }
    final expiry = DateTime.tryParse(expiresAt);
    final current = (now ?? DateTime.now()).toUtc();
    if (expiry == null ||
        !expiry.isUtc ||
        expiry.toIso8601String() != expiresAt ||
        !expiry.isAfter(current)) {
      throw const NotionImportPlanFormatException();
    }
    final cap = current.add(localLifetime);
    return NotionImportPlan._(
      bundle: bundle,
      fence: fence,
      token: token,
      expiresAt: expiry,
      localDeadline: expiry.isBefore(cap) ? expiry : cap,
    );
  }

  /// Device clocks may be wrong; the server's check remains authoritative.
  /// A clock jump or late request may cause a safe refusal and fresh preview.
  bool usable({
    required NotionBundle bundle,
    required NowaveSessionFence fence,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    return _token != null &&
        identical(this.bundle, bundle) &&
        this.fence.userId == fence.userId &&
        this.fence.generation == fence.generation &&
        expiresAt.isAfter(current) &&
        localDeadline.isAfter(current);
  }

  Duration remaining({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final duration = localDeadline.difference(current);
    return duration.isNegative ? Duration.zero : duration;
  }

  /// Consume before initiating the request: even an error or timeout cannot
  /// establish that no write occurred. A second attempt requires a new preview.
  String? consume({
    required NotionBundle bundle,
    required NowaveSessionFence fence,
    DateTime? now,
  }) {
    if (!usable(bundle: bundle, fence: fence, now: now)) {
      discard();
      return null;
    }
    final result = _token;
    _token = null;
    return result;
  }

  void discard() => _token = null;
}

/// Intentionally contains no response body or token in its message.
final class NotionImportPlanFormatException implements Exception {
  const NotionImportPlanFormatException();

  @override
  String toString() => 'Notion import preview plan is unavailable or invalid';
}
