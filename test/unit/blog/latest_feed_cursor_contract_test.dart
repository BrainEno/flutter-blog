import 'dart:convert';

import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's cursor parser, copied here as a **specification** rather than
/// imported (no-wave `apps/api/src/domain/cursor.ts`).
///
/// The feed degrades politely when a cursor is refused: the first continuation
/// falls back to offsets. That is exactly why the wire format needs a test of
/// its own - a change on either side would otherwise show up as a quietly
/// worse feed, not as a failure.
const int _serverMaxLength = 512;

/// The transport's gate before any decoding happens (`parseArticlePagination`):
/// a cursor is not trimmed, not empty, and at most 512 characters long.
/// `cursor` and `offset` in the same request, or a cursor with `sort=popular`,
/// are refused here too - they never reach the decoder.
bool _serverTransportAccepts(String cursor) =>
    cursor.isNotEmpty &&
    cursor.length <= _serverMaxLength &&
    cursor == cursor.trim();

/// `decodeCursor`: the separator splits at the *first* `|`, the timestamp is
/// checked for shape rather than merely parsed, and the id must be a UUID
/// because it is compared as half of a sort key rather than resolved.
({String at, String id})? _serverDecodeCursor(String? cursor) {
  if (cursor == null || cursor.isEmpty || cursor.length > _serverMaxLength) {
    return null;
  }
  final String decoded;
  try {
    decoded = utf8.decode(base64Url.decode(base64Url.normalize(cursor)));
  } on FormatException {
    return null;
  }
  final separator = decoded.indexOf('|');
  if (separator <= 0) return null;
  final at = decoded.substring(0, separator);
  final id = decoded.substring(separator + 1);
  if (!_isoMillisecond.hasMatch(at) || !_uuid.hasMatch(id)) return null;
  return (at: at, id: id);
}

final RegExp _isoMillisecond = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// `encodeCursor` as the server writes it: base64url, no padding.
String _encode(String raw) =>
    base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

const String _floorId = '00000000-0000-0000-0000-000000000000';

const String _boundary = '2026-11-01T12:34:56.123Z';

/// The same cursor as `encodeCursor` would write it: base64url, no padding.
const String _goldenCursor =
    'MjAyNi0xMS0wMVQxMjozNDo1Ni4xMjRafDAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAw'
    'MDAwMDAwMA';

BlogModel _blog(int n, String publishedAt) => BlogModel(
  id: 'article-$n',
  articleId: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  title: 'title',
  content: 'body',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2020),
  publishedAt: publishedAt,
);

LatestFeedContinuation _cursorFor(String publishedAt) =>
    LatestFeedContinuation.tryStart([_blog(1, publishedAt)])!;

void main() {
  test('the wire format is exactly what the server encodes', () {
    final cursor = _cursorFor(_boundary);
    expect(cursor.apiCursor, _goldenCursor);
    // No padding: Node's `base64url` writes none, and a stray `=` would end up
    // inside the decoded id and fail the server's UUID check.
    expect(cursor.apiCursor.contains('='), isFalse);
    expect(
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor.apiCursor),
      isTrue,
      reason: 'the token must survive a query string without re-encoding',
    );
    expect(cursor.apiCursor.length, lessThanOrEqualTo(_serverMaxLength));
  });

  test('the transport gate lets our cursor through and stops the rest', () {
    final ours = _cursorFor(_boundary).apiCursor;
    expect(_serverTransportAccepts(ours), isTrue);
    expect(_serverTransportAccepts(' $ours'), isFalse);
    expect(_serverTransportAccepts('$ours '), isFalse);
    expect(_serverTransportAccepts(''), isFalse);
    expect(_serverTransportAccepts('a' * (_serverMaxLength + 1)), isFalse);
    expect(_serverTransportAccepts('a' * _serverMaxLength), isTrue);
  });

  test('the server reads our cursor as the next millisecond and the floor', () {
    final cursor = _cursorFor(_boundary);
    final decoded = _serverDecodeCursor(cursor.apiCursor);
    expect(decoded, isNotNull);
    expect(
      decoded!.at,
      '2026-11-01T12:34:56.124Z',
      reason: 'a strict upper bound excludes the whole boundary millisecond',
    );
    expect(
      decoded.id,
      '00000000-0000-0000-0000-000000000000',
      reason: 'no UUID sorts below the floor, so nothing in the bound is lost',
    );
  });

  test('millisecond rollover stays inside the server timestamp shape', () {
    for (final boundary in [
      '2026-11-01T12:34:56.999Z',
      '2026-12-31T23:59:59.999Z',
      '2026-02-28T00:00:00.000Z',
    ]) {
      final cursor = _cursorFor(boundary);
      final decoded = _serverDecodeCursor(cursor.apiCursor);
      expect(
        decoded,
        isNotNull,
        reason: 'the rolled-over timestamp must still be ISO milliseconds',
      );
      final parsed = DateTime.parse(
        boundary,
      ).add(const Duration(milliseconds: 1));
      expect(decoded!.at, parsed.toIso8601String());
    }
  });

  test('a cursor that changes shape is one the server would refuse', () {
    final variants = <String, String>{
      'no separator': _encode('2026-11-01T12:34:56.124Z'),
      'no milliseconds': _encode('2026-11-01T12:34:56Z|$_floorId'),
      'offset instead of Z': _encode('2026-11-01T12:34:56.124+00:00|$_floorId'),
      'opaque id': _encode('2026-11-01T12:34:56.124Z|writer'),
      'two separators': _encode('2026-11-01T12:34:56.124Z|$_floorId|extra'),
      'empty': '',
      'too long': 'a' * (_serverMaxLength + 1),
    };
    for (final entry in variants.entries) {
      expect(
        _serverDecodeCursor(entry.value),
        isNull,
        reason: '${entry.key} must not pass for a cursor',
      );
    }
    // The separator is the *first* one, so an id holding another `|` is read
    // whole and then fails the UUID check rather than being silently split.
    final wellFormed = _encode('2026-11-01T12:34:56.124Z|$_floorId');
    expect(_serverDecodeCursor(wellFormed), isNotNull);
    // A cursor naming a *different* millisecond is not malformed - it simply
    // asks for another place. Only shape breaks are refused.
    final later = _encode('2026-11-01T12:34:57.123Z|$_floorId');
    expect(_serverDecodeCursor(later), isNotNull);
  });

  test('the local token carries only what the API already exposes', () {
    final cursor = _cursorFor(_boundary);
    final decoded = jsonDecode(cursor.token) as Map<String, dynamic>;
    expect(decoded.keys.toSet(), {'v', 'at', 'seen'});
    expect(decoded['v'], 1);
    expect(decoded['at'], _boundary);
    expect(
      (decoded['seen'] as List).every((id) => id is String),
      isTrue,
      reason: 'only public article ids and a public timestamp are kept',
    );
    expect(
      LatestFeedContinuation.tryDecode(cursor.token)!.apiCursor,
      cursor.apiCursor,
    );
  });

  test('the page size the cursor asks for stays inside the API limit', () {
    final dense = LatestFeedContinuation.tryDecode(
      jsonEncode({
        'v': 1,
        'at': _boundary,
        'seen': [
          for (var n = 0; n < 100; n++)
            '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
        ],
      }),
    )!;
    expect(dense.requestLimit, 100);
    expect(
      dense.requestLimit,
      lessThanOrEqualTo(100),
      reason: 'the API refuses a limit above 100 with a 400',
    );
    expect(_cursorFor(_boundary).requestLimit, 11);
  });
}
