import 'dart:collection';

import 'package:belog/features/blog/domain/entities/blog.dart';
import 'package:belog/features/blog/domain/offline_library/offline_library.dart';

/// Bounded, substring-based local article search.
///
/// The no-wave server intentionally uses substring search for Chinese and
/// mixed-language content. The local cache contains at most 250 articles for a
/// backend/locale namespace, so keeping the same understandable semantics as a
/// bounded in-memory scan is safer than adding a second full-text index which
/// could become stale on any cache write path.
class OfflineLibraryQuery {
  OfflineLibraryQuery._({required this.raw, required Iterable<String> terms})
    : terms = List.unmodifiable(terms);

  /// A deliberately small ceiling for a device-only query. It includes quotes
  /// and whitespace so a large pasted document does not trigger a scan.
  static const int maxLength = 120;

  /// Every term is required. The cap keeps matching and screen-reader wording
  /// predictable without turning the search box into a query language.
  static const int maxTerms = 8;

  /// A single long term offers little value and can make the excerpt awkward.
  static const int maxTermLength = 60;

  /// At most this many local results are rendered. The cache itself remains
  /// bounded to 250 rows; a result ceiling keeps large-text layouts useful.
  static const int maxResults = 100;

  /// Original, trimmed input. It is retained for the text field and never sent
  /// to an API or persisted.
  final String raw;

  /// Required phrases, normalized only for Unicode-aware Dart case matching.
  final List<String> terms;

  /// Parses words and double-quoted phrases. Quotes cannot be escaped; keeping
  /// the grammar deliberately tiny avoids surprising partial searches.
  static OfflineLibraryQueryParseResult parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const OfflineLibraryQueryParseResult.invalid(
        OfflineLibraryQueryIssue.empty,
      );
    }
    if (trimmed.length > maxLength) {
      return const OfflineLibraryQueryParseResult.invalid(
        OfflineLibraryQueryIssue.tooLong,
      );
    }

    final terms = <String>[];
    var index = 0;
    while (index < trimmed.length) {
      while (index < trimmed.length &&
          _isWhitespace(trimmed.codeUnitAt(index))) {
        index++;
      }
      if (index == trimmed.length) break;

      final startsQuote = trimmed.codeUnitAt(index) == _doubleQuote;
      final start = startsQuote ? ++index : index;
      while (index < trimmed.length &&
          (startsQuote
              ? trimmed.codeUnitAt(index) != _doubleQuote
              : !_isWhitespace(trimmed.codeUnitAt(index)))) {
        if (!startsQuote && trimmed.codeUnitAt(index) == _doubleQuote) {
          return const OfflineLibraryQueryParseResult.invalid(
            OfflineLibraryQueryIssue.invalidQuote,
          );
        }
        index++;
      }

      if (startsQuote) {
        if (index == trimmed.length) {
          return const OfflineLibraryQueryParseResult.invalid(
            OfflineLibraryQueryIssue.unclosedQuote,
          );
        }
        if (index == start) {
          return const OfflineLibraryQueryParseResult.invalid(
            OfflineLibraryQueryIssue.invalidQuote,
          );
        }
      }

      final term = trimmed.substring(start, index).trim();
      if (term.isEmpty) {
        return const OfflineLibraryQueryParseResult.invalid(
          OfflineLibraryQueryIssue.invalidQuote,
        );
      }
      if (term.length > maxTermLength) {
        return const OfflineLibraryQueryParseResult.invalid(
          OfflineLibraryQueryIssue.termTooLong,
        );
      }
      terms.add(_fold(term));
      if (terms.length > maxTerms) {
        return const OfflineLibraryQueryParseResult.invalid(
          OfflineLibraryQueryIssue.tooManyTerms,
        );
      }

      if (startsQuote) {
        index++; // consume the closing quote
        if (index < trimmed.length &&
            !_isWhitespace(trimmed.codeUnitAt(index))) {
          // `"a"b` is not silently converted into a surprising phrase.
          return const OfflineLibraryQueryParseResult.invalid(
            OfflineLibraryQueryIssue.invalidQuote,
          );
        }
      }
    }

    if (terms.isEmpty) {
      return const OfflineLibraryQueryParseResult.invalid(
        OfflineLibraryQueryIssue.empty,
      );
    }
    return OfflineLibraryQueryParseResult.valid(
      OfflineLibraryQuery._(raw: trimmed, terms: terms),
    );
  }

  /// Returns matching entries in stable relevance order. A reader who writes
  /// more than one term is asking for an AND search: each phrase must be found
  /// in at least one supported field. This avoids a broad OR result list that
  /// hides the article they were trying to recover offline.
  List<OfflineLibrarySearchResult> search(
    Iterable<OfflineLibraryEntry> entries,
  ) {
    final results = <OfflineLibrarySearchResult>[];
    for (final entry in entries) {
      final match = _match(entry.article);
      if (match == null) continue;
      results.add(
        OfflineLibrarySearchResult(
          entry: entry,
          fields: match.fields,
          score: match.score,
          bodyExcerpt: match.bodyExcerpt,
        ),
      );
    }
    results.sort(_compareResults);
    return List.unmodifiable(results.take(maxResults));
  }

  _ArticleMatch? _match(Blog article) {
    final title = _fold(article.title);
    final author = _fold(article.posterName ?? '');
    final tags = <String>[for (final tag in article.tags) _fold(tag)];
    final body = _fold(article.content);

    final fields = LinkedHashSet<OfflineLibraryMatchField>();
    var score = 0;
    int? firstBodyOffset;

    for (final term in terms) {
      final titleIndex = title.indexOf(term);
      final authorIndex = author.indexOf(term);
      final tagIndex = _firstTagIndex(tags, term);
      final bodyIndex = body.indexOf(term);
      if (titleIndex < 0 && authorIndex < 0 && tagIndex < 0 && bodyIndex < 0) {
        return null;
      }

      if (titleIndex >= 0) {
        fields.add(OfflineLibraryMatchField.title);
        score += titleIndex == 0 ? 1000 : 850;
      }
      if (tagIndex >= 0) {
        fields.add(OfflineLibraryMatchField.tag);
        final tag = tags[tagIndex];
        score += tag == term
            ? 760
            : tag.startsWith(term)
            ? 700
            : 620;
      }
      if (authorIndex >= 0) {
        fields.add(OfflineLibraryMatchField.author);
        score += authorIndex == 0 ? 520 : 430;
      }
      if (bodyIndex >= 0) {
        fields.add(OfflineLibraryMatchField.body);
        score += bodyIndex == 0 ? 240 : 180;
        firstBodyOffset ??= bodyIndex;
      }
    }

    // Field priority is a lexicographic part of relevance, rather than merely
    // another small bonus. Otherwise eight body-term hits could outrank one
    // title hit, which would contradict the catalog's documented order:
    // title, tags, author, then body. The accumulated precision bonus above is
    // intentionally smaller than one 10,000-point tier.
    score += _fieldTier(fields) * 10000;

    // A complete title phrase is especially likely to be what a reader
    // remembers. This tiebreaker leaves individual field matches meaningful.
    final fullQuery = _fold(raw);
    if (title.contains(fullQuery)) score += 500;

    return _ArticleMatch(
      fields: fields,
      score: score,
      bodyExcerpt: firstBodyOffset == null
          ? null
          : _bodyExcerpt(article.content, firstBodyOffset),
    );
  }

  static int _fieldTier(Set<OfflineLibraryMatchField> fields) {
    if (fields.contains(OfflineLibraryMatchField.title)) return 4;
    if (fields.contains(OfflineLibraryMatchField.tag)) return 3;
    if (fields.contains(OfflineLibraryMatchField.author)) return 2;
    return 1;
  }

  static int _compareResults(
    OfflineLibrarySearchResult left,
    OfflineLibrarySearchResult right,
  ) {
    final score = right.score.compareTo(left.score);
    if (score != 0) return score;
    final updated = right.entry.article.updatedAt.compareTo(
      left.entry.article.updatedAt,
    );
    if (updated != 0) return updated;
    return left.entry.article.id.compareTo(right.entry.article.id);
  }

  static int _firstTagIndex(List<String> tags, String term) {
    for (var index = 0; index < tags.length; index++) {
      if (tags[index].contains(term)) return index;
    }
    return -1;
  }

  /// Builds a plain text excerpt. The input is cached reader content, but it is
  /// never interpreted as Markdown/HTML here; Text renders it as text. Bounds
  /// are UTF-16 safe so a shortened excerpt cannot strand an emoji surrogate.
  static String _bodyExcerpt(String rawBody, int matchOffset) {
    if (rawBody.isEmpty) return '';
    final safeOffset = matchOffset.clamp(0, rawBody.length) as int;
    const before = 76;
    const after = 132;
    final rawStart = safeOffset > before ? safeOffset - before : 0;
    final rawEnd = safeOffset + after < rawBody.length
        ? safeOffset + after
        : rawBody.length;
    final start = _safeStart(rawBody, rawStart);
    final end = _safeEnd(rawBody, rawEnd);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < rawBody.length ? '…' : '';
    final compact = rawBody
        .substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ');
    return '$prefix${compact.trim()}$suffix';
  }

  static int _safeStart(String value, int proposed) {
    if (proposed <= 0 || proposed >= value.length) return proposed;
    final unit = value.codeUnitAt(proposed);
    return _isLowSurrogate(unit) &&
            _isHighSurrogate(value.codeUnitAt(proposed - 1))
        ? proposed - 1
        : proposed;
  }

  static int _safeEnd(String value, int proposed) {
    if (proposed <= 0 || proposed >= value.length) return proposed;
    final previous = value.codeUnitAt(proposed - 1);
    return _isHighSurrogate(previous) &&
            _isLowSurrogate(value.codeUnitAt(proposed))
        ? proposed + 1
        : proposed;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
  static bool _isWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

  static const int _doubleQuote = 0x22;
}

class _ArticleMatch {
  const _ArticleMatch({
    required this.fields,
    required this.score,
    required this.bodyExcerpt,
  });

  final Set<OfflineLibraryMatchField> fields;
  final int score;
  final String? bodyExcerpt;
}

String _fold(String value) => value.toLowerCase();
