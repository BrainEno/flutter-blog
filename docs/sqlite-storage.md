# SQLite storage

> 状态：active ｜ 最后核对：2026-11-19 @ 5d4fcfc

Drift on SQLite is the **only** local store: theme preference, drafts, the
bounded article cache, reading history, read-aloud preferences, the no-wave
session copy, profile cache and app metadata all live in `belog.sqlite`.

- `lib/core/storage/app_database.dart` owns the schema, the migrations and
  primitive row access (no feature or Flutter UI types; guarded by
  `tool/ci/check_core_dependencies.py`).
- The adapters that map rows to feature models live with their feature:
  `lib/features/blog/data/datasources/`, `lib/features/auth/data/datasources/`,
  `lib/core/theme/sqlite_theme_store.dart`, `lib/core/nowave/`.
- `id` in `blog_cache` is the article's route-facing id (slug); `article_id`
  keeps the server id when it differs.

## Schema versions

`schemaVersion` is 20. The v17 migration rebuilds cache and history tables to
add backend keys while retaining all old row values in an unattributed
namespace. It does not assign these rows to the currently configured server.
The v18 migration adds nullable TEXT `article_revision` / `expected_revision`
columns to public cache, account drafts and queued edits. Values are opaque
no-wave decimal int64 strings; NULL means an old or unsupported source and
authoring fails closed rather than issuing an unconditional update.
The v19 migration adds a nullable REAL `reading_history.progress`: where the
reader last left the article, as a share of its text (0–1). It is only ever
written for an article already in that account's history, is removed with
the entry, and NULL simply means "open at the top".
The v20 migration adds a nullable TEXT `blog_cache.summary`: the summary the
server sent with the row, so an offline feed shows the same excerpt as the
live one. It is display-only and never feeds an edit (writes still require a
fresh `serverSummary`); NULL is a row cached before v20, and the list then cuts
an excerpt from the body.

| Version | Change |
| --- | --- |
| 1 | Initial SQLite schema: `metadata`, `theme`, `drafts`, `blog_cache` |
| 2 | `blog_cache.article_id` |
| 3 | Feed index on `blog_cache(updated_at DESC, id DESC)` |
| 4 | `reading_history` |
| 5 | `blog_cache.document_json` (structured bodies) and read-aloud preferences |
| 6 | `account_drafts`, backend/owner columns for drafts, profile cache |
| 7 | `blog_cache.content_locale`: both content languages cached side by side (#108) |
| 8 | `publish_queue` and its due index: publishes the server has not accepted yet ([发布队列](publish-queue.md)) |
| 9 | `publish_queue.cover_url`: the cover a queued send already uploaded, so a retry reuses the asset instead of uploading it again |
| 10 | `publish_queue.kind` and `target_id`: the queue now carries edits of published articles, not only new ones |
| 11 | `publish_queue.locale` |
| 12 | Category selections in drafts and queue |
| 13 | Categories in cached articles |
| 14 | Account/backend/edition-scoped structured body recovery |
| 15 | Structured recovery metadata |
| 16 | Exclusive structured intermediate text buffer |
| 17 | Backend-scoped article cache and reading history, and cache access index |
| 18 | Opaque no-wave article revision strings in cache, account drafts and queued edits; safe conditional update recovery |
| 19 | `reading_history.progress`: where the reader left each article, for 「从上次停下的地方继续」 |
| 20 | `blog_cache.summary`: the server summary, for the excerpt under each title in an offline feed |

The production file connection sets SQLite WAL and a 5000 ms busy timeout before
migrations. New cache writes prune least-recently-accessed entries to 250 per
backend and content language. Access is tracked best-effort: if a touch cannot
be written, the offline read still succeeds, but the row may be evicted earlier.
This is a row-count limit, not a byte quota or TTL; large individual articles,
multiple backends and the preserved legacy namespace can still consume space.

## Android backup boundary

`belog.sqlite` can hold a session fallback containing access/refresh tokens when
platform secure storage is unavailable, as well as unpublished drafts, queued
writes, reading history, article cache and reader preferences. Android therefore
sets `android:allowBackup="false"` in the release manifest. It also references
explicit `res/xml/backup_rules.xml` and `data_extraction_rules.xml` deny-lists
for legacy full backup and Android 12+ cloud/device-transfer parsers; each
excludes the app root, files, databases, preferences and external app storage.
The manifest flag is the primary block, not encryption or a promise that every
OEM migration/forensics tool can never copy a device. The checked-in XML is a
regression-tested defense-in-depth policy, not a user-managed backup/export
feature.

This applies to Android app data only. iOS/macOS/Windows backup, restore,
enterprise management and filesystem-retention policies remain platform or
deployment concerns. Before an upgrade, downgrade, device migration or manual
copy of private app data, treat the database as sensitive and do not assume a
restored secure-storage key can decrypt an old session.

## Offline Library

The Search tab's Offline Library is a read-only catalog over **only the active
backend + content-language** `blog_cache` rows. It has no schema migration or
FTS side table: the already bounded 250-row namespace is read once, then title,
author, tags and flattened reader body text are matched in memory with bounded
substring terms. Listing/searching does not touch `accessed_at`; opening an
article through the usual viewer remains an ordinary cache read and may update
its LRU timestamp.

The catalog shows an estimate of the row-owned UTF-8 text/JSON/URL bytes. It is
not SQLite/WAL page usage, the app's total data use, or the image cache size.
Its confirmed clear action deletes only `blog_cache` rows for the active backend
and language. It does not clear drafts, structured recoveries, publish queue,
reading history, profile/session data or any other cache namespace. See
[Offline Library](offline-library.md) for the user-visible behavior and query
limits.

Older cache and history records do not identify their backend. They remain in an
unattributed namespace and are not displayed or cleared by any normal backend
session. This prevents cross-server disclosure but means old offline articles
and history will not appear after upgrade; old history remains on disk and is
not deleted by sign-out. When such history exists, the history page offers an
explicit device-wide deletion with a warning that it may include other accounts.
No automatic owner assignment or cleanup is attempted.
Back up the app data directory before migration. Downgrade and WAL operation on
real devices have not been verified; older clients may not understand v20 and
must not be assumed safe to open the upgraded file.

## Isar is gone (#107)

Isar was the store before SQLite. Upstream `isar` stopped at 3.1.0+1, and after
the SQLite migration the app kept only a **one-time reader** so that devices with
an existing `default.isar` could import their data. That reader still shipped a
native engine, generated schemas and a fixture generator for zero live use, so
it was removed completely:

- dependencies: `isar_community`, `isar_community_flutter_libs`,
  `isar_community_generator`;
- code: the removed legacy Isar storage directory (generated schemas),
  `AppDatabase.importLegacyIfNeeded`, `tool/legacy_isar_fixture/`,
  `test/fixtures/legacy_isar_3_1_0/`, the Isar import tests, `build.yaml` and
  the analyzer excludes that existed only for the generated code.

What this means for a device that still has `default.isar`:

- the file is **never opened, imported or deleted**; the app only checks that it
  exists and logs one debug line (`default.isar` found, importer removed). A
  marker in the SQLite `metadata` table keeps later launches quiet;
- affected local data is the theme choice, unsent drafts and the cached
  articles. The cache refills from the network; drafts are not recoverable
  in-app;
- to migrate such a device, install a build that still contains the importer
  (any build from a commit before this change) **first**, launch it once so the
  `isar_import_v1` marker is committed, and only then upgrade. After the
  upgrade there is no path back to the Isar file;
- no published release is known to contain the importer, so check which build a
  device actually ran before promising a migration.

The unclaimed-draft export (`tool/export_unclaimed_drafts.py`,
[docs/unclaimed-drafts.md](unclaimed-drafts.md)) only reads SQLite rows that
already exist; it cannot read an Isar file.

## Former notes on the migration (kept for context)

The reader copied `default.isar` to a temporary directory before opening it, so
a failed or interrupted attempt could not alter the only copy, and it committed
the imported rows together with the marker in one transaction. The importer
picked the highest-ID theme, all drafts and all cached posts, and collapsed
cache rows with duplicate business ids in legacy id order. SQLite writes were
never synchronized back to Isar.
