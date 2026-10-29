# Legacy Isar fixture generator

`test/fixtures/legacy_isar_3_1_0/default.isar` is a real database written by
the abandoned `isar 3.1.0+1` package using the original generator's schemas
(the `lib/` copies in this package are the pre-migration collection sources).
The storage test suite opens it through the app's `importLegacyIfNeeded` to
prove that the isar_community-based reader (issue #3) still reads databases
created by old app versions.

## Regenerating the fixture

From the repository root (requires the pinned Flutter/Dart toolchain and
network access to pub.dev and the isar GitHub releases for the host binary):

```bash
cd tool/legacy_isar_fixture
dart pub get
dart run bin/create.dart ../../test/fixtures/legacy_isar_3_1_0/default.isar
```

Commit the resulting file together with any schema change in `lib/`. The
schemas are frozen legacy definitions: never rename classes or properties,
or databases written by released app versions become unreadable.

## Why the enum is redeclared

This package is pure Dart, so it cannot import `flutter/material.dart`. The
local `ThemeMode` in `lib/theme_preference.dart` mirrors the Flutter enum's
value order; `@enumerated` persists the enum index, so the bytes written are
identical to the old app's.
