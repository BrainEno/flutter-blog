import 'dart:collection';

import 'package:belog/features/blog/domain/entities/blog.dart';

/// A read-only view of the public article cache in exactly one current
/// backend/content-language namespace.
///
/// The cache never represents every article on the server: it is a bounded
/// best-effort read cache populated by the latest feed and article detail
/// reads. This value deliberately carries no backend URL. The UI can truthfully
/// say "this server" without turning a configured endpoint into a shareable
/// or user-visible data value.
class OfflineLibrarySnapshot {
  OfflineLibrarySnapshot({
    required this.locale,
    required this.summary,
    required Iterable<OfflineLibraryEntry> entries,
  }) : entries = UnmodifiableListView(List<OfflineLibraryEntry>.of(entries));

  /// The content edition that was used for every row in [entries].
  final String locale;

  /// Aggregate information calculated by SQLite for this exact namespace.
  final OfflineLibrarySummary summary;

  /// Entries ordered by most recently accessed local copy first.
  final List<OfflineLibraryEntry> entries;

  /// A successful empty read, useful after a confirmed clear. It is not used
  /// as a fallback for another locale or API server.
  factory OfflineLibrarySnapshot.empty({required String locale}) =>
      OfflineLibrarySnapshot(
        locale: locale,
        summary: const OfflineLibrarySummary(),
        entries: const [],
      );

  bool get isEmpty => entries.isEmpty;

  int get length => entries.length;
}

/// Small, local-only cache accounting information.
///
/// [estimatedBytes] counts SQLite values that make up an article cache row
/// (text, JSON, URLs and metadata). It does not include SQLite page overhead,
/// WAL pages, the application database's unrelated tables, or any bytes held by
/// the image package's disk cache, so callers must never present it as exact
/// device storage consumption.
class OfflineLibrarySummary {
  const OfflineLibrarySummary({
    this.articleCount = 0,
    this.estimatedBytes = 0,
    this.newestAccessedAt,
  }) : assert(articleCount >= 0),
       assert(estimatedBytes >= 0);

  final int articleCount;
  final int estimatedBytes;
  final DateTime? newestAccessedAt;

  bool get isEmpty => articleCount == 0;
}

/// One publicly readable cached article plus local, non-synchronized metadata.
class OfflineLibraryEntry {
  const OfflineLibraryEntry({
    required this.article,
    required this.lastAccessedAt,
    required this.estimatedBytes,
  }) : assert(estimatedBytes >= 0);

  /// The cached public article. Drafts are intentionally never written to this
  /// cache and therefore cannot enter an offline library entry.
  final Blog article;

  /// The local LRU timestamp, not the server update time and not a reading
  /// history entry. Browsing the library does not update it; opening an item in
  /// the normal viewer may update it through the existing cache read path.
  final DateTime lastAccessedAt;

  /// A per-row estimate that contributes to [OfflineLibrarySummary].
  final int estimatedBytes;
}

/// Which reader-visible field satisfied a local substring query.
enum OfflineLibraryMatchField { title, author, tag, body }

/// A matched cache entry. Ranking is deterministic and only expresses local
/// relevance; it is not a server ranking, popularity signal, or a promise that
/// an article is newly published.
class OfflineLibrarySearchResult {
  OfflineLibrarySearchResult({
    required this.entry,
    required Iterable<OfflineLibraryMatchField> fields,
    required this.score,
    this.bodyExcerpt,
  }) : fields = UnmodifiableSetView(
         LinkedHashSet<OfflineLibraryMatchField>.of(fields),
       ),
       assert(score >= 0);

  final OfflineLibraryEntry entry;
  final Set<OfflineLibraryMatchField> fields;

  /// Internal deterministic ordering value. It is intentionally not shown in
  /// the UI: exposing an arbitrary local score would make it look like a
  /// backend search ranking.
  final int score;

  /// A compact, plain-text body passage around a matching phrase. Null means
  /// this entry matched only title, author or tags.
  final String? bodyExcerpt;

  bool get hasBodyExcerpt => bodyExcerpt != null && bodyExcerpt!.isNotEmpty;
}

/// The result of parsing local search input before any cache scan begins.
///
/// A bad query is a local validation answer, not an exception. That lets the
/// UI explain the limit and, importantly, avoids scanning article bodies for
/// accidental enormous pasted input.
class OfflineLibraryQueryParseResult {
  const OfflineLibraryQueryParseResult._({this.query, this.issue});

  const OfflineLibraryQueryParseResult.valid(OfflineLibraryQuery value)
    : this._(query: value);

  const OfflineLibraryQueryParseResult.invalid(OfflineLibraryQueryIssue value)
    : this._(issue: value);

  final OfflineLibraryQuery? query;
  final OfflineLibraryQueryIssue? issue;

  bool get isValid => query != null;
}

/// Reasons a local query is not scanned.
enum OfflineLibraryQueryIssue {
  empty,
  tooLong,
  tooManyTerms,
  termTooLong,
  unclosedQuote,
  invalidQuote,
}
