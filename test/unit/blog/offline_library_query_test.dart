import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library_query.dart';
import 'package:flutter_test/flutter_test.dart';

OfflineLibraryEntry _entry(
  String id, {
  required String title,
  String author = 'Reader',
  List<String> tags = const [],
  String body = '',
  int day = 1,
}) => OfflineLibraryEntry(
  article: Blog(
    id: id,
    title: title,
    content: body,
    posterId: 'author-$id',
    posterName: author,
    imageUrl: '',
    tags: tags,
    updatedAt: DateTime.utc(2026, 1, day),
    locale: 'en',
  ),
  lastAccessedAt: DateTime.utc(2026, 1, day),
  estimatedBytes: title.length + body.length,
);

OfflineLibraryQuery _query(String text) {
  final parsed = OfflineLibraryQuery.parse(text);
  expect(parsed.isValid, isTrue, reason: 'expected a valid local query: $text');
  return parsed.query!;
}

void main() {
  test('searches title author tags and reader body with AND semantics', () {
    final entries = [
      _entry(
        'title',
        title: 'Rain notes',
        author: 'Mira',
        tags: const ['Weather'],
        body: 'A quiet walk.',
      ),
      _entry(
        'body',
        title: 'Field journal',
        author: 'Lin',
        tags: const ['Nature'],
        body: 'Rain falls on a silent garden.',
        day: 2,
      ),
      _entry(
        'both',
        title: 'Rain garden',
        author: 'Mira',
        tags: const ['Nature'],
        body: 'A silent garden remembers the rain.',
        day: 3,
      ),
    ];

    final results = _query('rain "silent garden"').search(entries);

    expect(results.map((result) => result.entry.article.id), ['both', 'body']);
    expect(
      results.first.fields,
      containsAll(<OfflineLibraryMatchField>[
        OfflineLibraryMatchField.title,
        OfflineLibraryMatchField.body,
      ]),
    );
    expect(results.last.fields, contains(OfflineLibraryMatchField.body));
    expect(results.last.bodyExcerpt, contains('silent garden'));
  });

  test(
    'title and tag matches rank above body-only matches deterministically',
    () {
      final results = _query('rain').search([
        _entry(
          'body-newer',
          title: 'Journal',
          body: 'A sudden rain passed.',
          day: 3,
        ),
        _entry('tag', title: 'Notebook', tags: const ['rain']),
        _entry('title', title: 'Rain report', body: 'dry'),
        _entry('title-same-score-b', title: 'Rain song', day: 2),
        _entry('title-same-score-a', title: 'Rain song', day: 2),
      ]);

      expect(results.map((result) => result.entry.article.id), [
        'title-same-score-a',
        'title-same-score-b',
        'title',
        'tag',
        'body-newer',
      ]);
    },
  );

  test('field priority keeps any title hit above many body-term hits', () {
    final query = _query('one two three four five six seven eight');
    final results = query.search([
      _entry(
        'body-only',
        title: 'Journal',
        body: 'one two three four five six seven eight',
        day: 2,
      ),
      _entry(
        'title',
        title: 'One remembered phrase',
        body: 'two three four five six seven eight',
      ),
    ]);

    expect(results.map((result) => result.entry.article.id), [
      'title',
      'body-only',
    ]);
  });

  test(
    'preserves substring semantics for Chinese and case-insensitive Latin text',
    () {
      final results = _query('雨 ÉCLAIR').search([
        _entry('hit', title: '下着雨的夜晚', body: 'An éclair waits by the window.'),
        _entry('miss', title: '下着雨的夜晚', body: 'A cake waits.'),
      ]);

      expect(results.single.entry.article.id, 'hit');
      expect(results.single.fields, contains(OfflineLibraryMatchField.title));
      expect(results.single.fields, contains(OfflineLibraryMatchField.body));
    },
  );

  test(
    'body excerpt stays plain text and does not split an emoji surrogate',
    () {
      final body = '${'x' * 80}😀 rain ${'y' * 180}';
      final result = _query(
        'rain',
      ).search([_entry('emoji', title: 'Title', body: body)]).single;

      expect(result.bodyExcerpt, contains('rain'));
      expect(result.bodyExcerpt, isNot(contains('<')));
      expect(() => result.bodyExcerpt!.runes.toList(), returnsNormally);
    },
  );

  test('invalid or excessive input is rejected before an article scan', () {
    expect(OfflineLibraryQuery.parse('').issue, OfflineLibraryQueryIssue.empty);
    expect(
      OfflineLibraryQuery.parse('"unfinished').issue,
      OfflineLibraryQueryIssue.unclosedQuote,
    );
    expect(
      OfflineLibraryQuery.parse('one"two').issue,
      OfflineLibraryQueryIssue.invalidQuote,
    );
    expect(
      OfflineLibraryQuery.parse(
        'x' * (OfflineLibraryQuery.maxLength + 1),
      ).issue,
      OfflineLibraryQueryIssue.tooLong,
    );
    expect(
      OfflineLibraryQuery.parse(
        List.filled(OfflineLibraryQuery.maxTerms + 1, 'term').join(' '),
      ).issue,
      OfflineLibraryQueryIssue.tooManyTerms,
    );
    expect(
      OfflineLibraryQuery.parse(
        'x' * (OfflineLibraryQuery.maxTermLength + 1),
      ).issue,
      OfflineLibraryQueryIssue.termTooLong,
    );
  });

  test('results stop at a stable local limit', () {
    final results = _query('needle').search([
      for (var index = 0; index < OfflineLibraryQuery.maxResults + 4; index++)
        _entry(
          'id-${index.toString().padLeft(3, '0')}',
          title: 'needle',
          day: 1,
        ),
    ]);

    expect(results, hasLength(OfflineLibraryQuery.maxResults));
    expect(results.first.entry.article.id, 'id-000');
    expect(results.last.entry.article.id, 'id-099');
  });
}
