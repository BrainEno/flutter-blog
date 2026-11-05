# SQLite storage

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

`schemaVersion` is 9. Migrations only ever add tables/columns/indexes; no user
data is rewritten or dropped.

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

Downgrade is not supported: an older build opening a v9 file may show rows in
the wrong scope. Back up the app data directory before experimenting with
older builds.

## Isar is gone (#107)

Isar was the store before SQLite. Upstream `isar` stopped at 3.1.0+1, and after
the SQLite migration the app kept only a **one-time reader** so that devices with
an existing `default.isar` could import their data. That reader still shipped a
native engine, generated schemas and a fixture generator for zero live use, so
it was removed completely:

- dependencies: `isar_community`, `isar_community_flutter_libs`,
  `isar_community_generator`;
- code: `lib/core/storage/legacy/` (generated schemas),
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
