# Isar to SQLite migration (draft, not release-ready)

The active store in this branch uses Drift with SQLite. The existing Isar 3.1
package is still required *only* to import old data. This is not yet a complete
removal of Isar, and this branch must not be released until its native migration
bridge is made 16 KiB compatible and verified on a 16 KiB Android environment.

## Data handling

On startup, before any UI gets the SQLite database, the importer looks for the
old `default.isar`. It opens the original schemas, reads the highest-ID theme,
all drafts and cached posts, then imports everything and the completion marker
in one SQLite transaction. An exception rolls that transaction back; the app
fails startup rather than silently discarding local data. The original Isar
files are not deleted. Cache rows with duplicate business IDs are collapsed in
legacy ID order. Subsequent SQLite writes are not synchronized back to Isar:
a downgrade will see the old snapshot, not later SQLite edits. Do not ship this
as a seamless rollback mechanism without a tested export/restore path.

## Release blocker: old native library

The PR build on 29 October 2026 found every `libisar.so` ABI still has ELF LOAD
alignment of `0x1000`, including arm64. See [diagnostic run
40829729284](https://github.com/BrainEno/flutter-blog/actions/runs/40829729284)
for per-ABI `readelf -lW` output. Simply switching the live store to SQLite
does not make this binary 16 KiB compatible. The Android CI check examines all
ELF LOAD segments and APK ZIP alignment, so this branch intentionally remains
blocked until the bridge and any other failing libraries are fixed.

A complete solution needs a reproducible, supported 16 KiB-safe legacy reader
(or a proven two-stage migration preserving drafts on all supported devices),
a release APK checked with NDK `llvm-readelf` and `zipalign -c -P 16`, and
upgrade/downgrade validation on a real or emulated 16 KiB Android environment.
Do not remove the old reader or clear its database merely to pass the check.
The generated model and analyzer constraints still depend on old Isar until
that migration bridge can be retired safely.
