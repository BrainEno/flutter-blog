# Unreferenced source images

These files were inside `assets/images/` and therefore bundled into every APK,
but no Dart code, pubspec entry, native launch screen or CI script referenced
them. They were moved here (#107 cleanup) so they stay in the repository
without shipping: `assets/images/` is included as a directory, so anything left
in it ends up in the bundle.

- `sffinks.png` (1.1 MiB) - no reference anywhere in the tree.
- `icon.png` (132 KiB) - the launcher icon source is `assets/icons/logo.png`
  (`flutter_launcher_icons` in `pubspec.yaml`); this file is a leftover.
- `splash.png` (28 KiB) - only referenced by `flutter_native_splash.yaml`,
  which was deleted because `flutter_native_splash` is not a dependency and CI
  never runs it. The committed native launch screens are the real ones.

Move a file back into `assets/` and reference it explicitly if it is needed
again.
