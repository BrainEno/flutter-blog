# Isar to SQLite migration

The active theme, draft and cached-article stores use Drift/SQLite. Isar is
retained only as a one-time reader for existing local databases; it is not the
active storage engine. Since issue #3 the reader runs on the maintained
`isar_community` 3.4.1 packages (same Isar 3 API and on-disk format).

## Existing data and rollback

At startup, before exposing SQLite to the UI, the importer checks for
`default.isar`, copies it to a temporary directory and opens the copy using the
original schemas. It imports the highest-ID theme, all drafts and cached posts.
Data and the completion marker commit in the same SQLite transaction. Failure
rolls back that transaction and stops startup rather than silently discarding
local data. The original Isar files are not opened or deleted by the importer;
the temporary copy requires free disk space and is deleted after use. Cache
rows with duplicate business IDs are collapsed in legacy ID order.

SQLite writes are not synchronized back to the Isar snapshot. A downgrade will
see old data rather than edits made after migration, and later Isar edits will
not be automatically re-imported once the SQLite marker exists. A seamless
rollback/export strategy remains unimplemented. Test on representative old
databases and take a backup before a production rollout.

## Android 16 KiB compatibility

The abandoned `isar` 3.1.0+1 published Android binaries with 4 KiB ELF
segments. `isar_community_flutter_libs` (since 3.2.0) ships 16 KiB-aligned
Android binaries, so the app now packages the maintained prebuilt reader
instead of the previous source-built replacement; the Rust build under
`tool/legacy_isar` was removed with that change.

CI checks every APK `.so` LOAD segment with NDK `llvm-readelf` and APK ZIP
alignment using `zipalign -c -P 16 -v 4`, and the evidence log is uploaded as
a build artifact. The legacy database import and failure/rollback tests use a
real temporary Isar database on Linux. Old-data compatibility is additionally
covered by `test/unit/storage/legacy_isar_31_import_test.dart`, which imports
a fixture database written by the original `isar 3.1.0+1` (regenerable via
`tool/legacy_isar_fixture`).

The APK ELF and ZIP checks are not a substitute for runtime testing: a
migration of old production data on a real or emulated 16 KiB Android device,
iOS runtime behavior, older database variants and a downgrade/restore procedure
have not yet been verified. The Isar reader remains until there is a safe
strategy to retire the migration bridge.
