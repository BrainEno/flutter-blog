# Isar to SQLite migration

The active theme, draft and cached-article stores use Drift/SQLite. Isar 3.1 is
retained only as a one-time reader for existing local databases; it is not the
active storage engine. This is a transitional dependency, not a migration to
Isar Community.

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

The original published `isar_flutter_libs` Android binaries have 4 KiB ELF
segments. `tool/legacy_isar/build_android.sh` builds the original Isar 3.1
reader with 16 KiB alignment for arm64-v8a, armeabi-v7a and x86_64, with fixed
Isar and libmdbx commits, Cargo lockfile and Rust toolchain. Gradle builds the
reader before merging native libraries and packages it instead of the old
plugin binary. The reader is only needed when importing an old database.

Android builds require a Linux or macOS host with Bash, Python 3, Git, make,
rustup, libclang and network access for the pinned source and Cargo crates.
Rust 1.99.1 and its Android targets are installed by rustup if missing; the
Android NDK version comes from `android/app/build.gradle`. On a clean build the
native reader must be rebuilt, so initial Android builds take longer. Generated
source and binaries stay under `build/` and are not committed.

CI verifies that every packaged Isar reader byte-for-byte matches the rebuilt
binary, checks every APK `.so` LOAD segment with NDK `llvm-readelf`, and checks
APK ZIP alignment using `zipalign -c -P 16 -v 4`. The legacy database import
and failure/rollback tests use a real temporary Isar database on Linux.

The APK ELF and ZIP checks are not a substitute for runtime testing: a
migration of old production data on a real or emulated 16 KiB Android device,
iOS runtime behavior, older database variants and a downgrade/restore procedure
have not yet been verified. The Isar generator and native reader remain until
there is a safe strategy to retire the migration bridge.
