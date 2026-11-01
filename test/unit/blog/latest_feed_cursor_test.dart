import 'dart:convert';
import 'dart:math';

import 'package:belog/features/blog/data/datasources/latest_feed_cursor.dart';
import 'package:belog/features/blog/data/models/blog_model.dart';
import 'package:flutter_test/flutter_test.dart';

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

BlogModel _blog(int id, String? publishedAt, {String? slug}) => BlogModel(
  id: slug ?? 'article-$id',
  articleId: _uuid(id),
  title: 'title',
  content: 'body',
  posterId: 'author',
  imageUrl: '',
  tags: const [],
  updatedAt: DateTime.utc(2020),
  publishedAt: publishedAt,
);

class _StoredRow {
  const _StoredRow(this.blog, this.microseconds);

  final BlogModel blog;
  final int microseconds;
}

void main() {
  const t = '2026-11-01T12:34:56.123Z';
  const older = '2026-11-01T12:34:56.122Z';

  test('uses the next millisecond as a strict upper bound', () {
    final cursor = LatestFeedContinuation.tryStart([
      _blog(1, '2026-11-01T12:34:57.000Z'),
      _blog(2, t),
      _blog(3, t),
    ])!;
    expect(cursor.publishedAt, t);
    expect(cursor.seenIds, {_uuid(2), _uuid(3)});
    expect(cursor.requestLimit, 12);
    expect(
      utf8.decode(base64Url.decode(base64Url.normalize(cursor.apiCursor))),
      '2026-11-01T12:34:56.124Z|00000000-0000-0000-0000-000000000000',
    );
    final restored = LatestFeedContinuation.tryDecode(cursor.token)!;
    expect(restored.publishedAt, t);
    expect(restored.seenIds, cursor.seenIds);
  });

  test('overlaps and deduplicates same-millisecond rows in server order', () {
    // PostgreSQL microseconds can make UUIDs appear in any order after the
    // timestamps are truncated to milliseconds in the REST representation.
    final cursor = LatestFeedContinuation.tryStart([_blog(1, t)])!;
    final slice = cursor.advance([
      _blog(1, t),
      _blog(900, t),
      _blog(2, t),
      _blog(3, older),
    ]);
    expect(slice.blogs.map((blog) => blog.id), [
      'article-900',
      'article-2',
      'article-3',
    ]);
    final next = LatestFeedContinuation.tryDecode(slice.nextCursor!)!;
    expect(next.publishedAt, older);
    expect(next.seenIds, {_uuid(3)});
  });

  test(
    'retains all seen IDs when the next page ends in the same millisecond',
    () {
      final cursor = LatestFeedContinuation.tryStart([_blog(1, t)])!;
      final slice = cursor.advance([_blog(1, t), _blog(2, t), _blog(3, t)]);
      final next = LatestFeedContinuation.tryDecode(slice.nextCursor!)!;
      expect(next.seenIds, {_uuid(1), _uuid(2), _uuid(3)});
      expect(next.requestLimit, 13);
    },
  );

  test('a short window is the end but a full non-progress window is not', () {
    final seen = List.generate(100, (index) => _uuid(index));
    final cursor = LatestFeedContinuation.tryDecode(
      jsonEncode({'v': 1, 'at': t, 'seen': seen}),
    )!;
    expect(cursor.requestLimit, 100);
    expect(
      () => cursor.advance(List.generate(100, (index) => _blog(index, t))),
      throwsA(isA<LatestFeedCursorTooDense>()),
    );
    final short = cursor.advance(List.generate(99, (index) => _blog(index, t)));
    expect(short.blogs, isEmpty);
    expect(short.nextCursor, isNull);
  });

  test('does not report a partial dense window as the end of the feed', () {
    final seen = List.generate(95, (index) => _uuid(index));
    final cursor = LatestFeedContinuation.tryDecode(
      jsonEncode({'v': 1, 'at': t, 'seen': seen}),
    )!;
    expect(
      () => cursor.advance(List.generate(100, (index) => _blog(index, t))),
      throwsA(isA<LatestFeedCursorTooDense>()),
    );
  });

  test('validates the whole page against the upper bound and ordering', () {
    final cursor = LatestFeedContinuation.tryStart([_blog(1, t)])!;
    final cases = <List<BlogModel>>[
      [_blog(2, '2026-11-01T12:34:56.124Z')],
      [_blog(2, older), _blog(3, t)],
      [_blog(2, t), _blog(2, t)],
      [_blog(2, t, slug: 'same'), _blog(3, t, slug: 'same')],
      [_blog(2, null)],
      List.generate(12, (index) => _blog(index + 10, t)),
    ];
    for (final rows in cases) {
      expect(
        () => cursor.advance(rows),
        throwsA(isA<LatestFeedCursorUnavailable>()),
        reason: 'an ignored cursor or malformed page must not be accepted',
      );
    }
  });

  test('rejects unsafe timestamps, UUIDs, duplicate IDs, and bad tokens', () {
    expect(LatestFeedContinuation.tryStart([_blog(1, null)]), isNull);
    expect(
      LatestFeedContinuation.tryStart([_blog(1, '2026-02-30T00:00:00.000Z')]),
      isNull,
    );
    expect(
      LatestFeedContinuation.tryStart([_blog(1, '9999-12-31T23:59:59.999Z')]),
      isNull,
    );
    expect(LatestFeedContinuation.tryStart([_blog(1, t), _blog(1, t)]), isNull);
    expect(LatestFeedContinuation.tryDecode('not-json'), isNull);
    expect(LatestFeedContinuation.tryDecode(' ' * 8193), isNull);
    expect(
      LatestFeedContinuation.tryDecode(
        jsonEncode({
          'v': 1,
          'at': t,
          'seen': [_uuid(1), _uuid(1)],
        }),
      ),
      isNull,
    );
    expect(
      LatestFeedContinuation.tryDecode(
        jsonEncode({
          'v': 2,
          'at': t,
          'seen': [_uuid(1)],
        }),
      ),
      isNull,
    );
    expect(
      LatestFeedContinuation.tryDecode(
        jsonEncode({
          'v': 1,
          'at': t,
          'seen': ['not-a-uuid'],
        }),
      ),
      isNull,
    );
  });

  test('walks randomized microsecond data completely or stops safely', () {
    final random = Random(131133);
    final baseMs = DateTime.utc(2026, 11).millisecondsSinceEpoch;
    for (var run = 0; run < 200; run++) {
      final count = random.nextInt(260);
      final buckets = 1 + random.nextInt(20);
      final rows =
          List.generate(count, (index) {
            final millis = baseMs + random.nextInt(buckets);
            final micros = millis * 1000 + random.nextInt(1000);
            final timestamp = DateTime.fromMillisecondsSinceEpoch(
              millis,
              isUtc: true,
            ).toIso8601String();
            return _StoredRow(_blog(index, timestamp), micros);
          })..sort((a, b) {
            final time = b.microseconds.compareTo(a.microseconds);
            return time != 0
                ? time
                : b.blog.articleId.compareTo(a.blog.articleId);
          });
      final expected = rows.map((row) => row.blog.id).toList();
      final first = rows.take(10).map((row) => row.blog).toList();
      final read = [...first];
      if (first.length < 10) {
        expect(read.map((b) => b.id), expected);
        continue;
      }
      var cursor = LatestFeedContinuation.tryStart(first)!;
      var dense = false;
      for (var page = 0; page < 100; page++) {
        final upperMs =
            DateTime.parse(cursor.publishedAt).millisecondsSinceEpoch + 1;
        final window = rows
            .where((row) => row.microseconds < upperMs * 1000)
            .take(cursor.requestLimit)
            .map((row) => row.blog)
            .toList();
        try {
          final slice = cursor.advance(window);
          read.addAll(slice.blogs);
          if (slice.blogs.length < 10) break;
          cursor = LatestFeedContinuation.tryDecode(slice.nextCursor!)!;
        } on LatestFeedCursorTooDense {
          dense = true;
          break;
        }
      }
      final actual = read.map((blog) => blog.id).toList();
      expect(actual.toSet(), hasLength(actual.length), reason: 'run $run');
      expect(
        actual,
        dense ? expected.take(actual.length).toList() : expected,
        reason: 'run $run must not silently skip or reorder rows',
      );
    }
  });

  test('model preserves server publishedAt rather than deriving updatedAt', () {
    final model = BlogModel.fromNowaveArticle({
      'id': _uuid(1),
      'slug': 'one',
      'title': 'title',
      'contentBlocksVersion': 0,
      'contentBlocks': <Map<String, dynamic>>[],
      'publishedAt': t,
      'updatedAt': '2020-01-01T00:00:00.000Z',
    });
    expect(model.publishedAt, t);
    expect(model.copyWith(title: 'edited').publishedAt, t);
  });
}
