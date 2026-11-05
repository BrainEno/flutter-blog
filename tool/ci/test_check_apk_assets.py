import pathlib
import tempfile
import unittest
import zipfile

from check_apk_assets import (
    DEFAULT_BUDGET_BYTES,
    analyze,
    apk_entries,
    asset_table,
    bucket_of,
    bundled_assets,
    declared_assets,
    manifest_without_asset_list,
    oversized_assets,
    size_report,
    source_usage_text,
    undeclared_assets,
    unreferenced_assets,
)

PUBSPEC = '''
name: belog

flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/images/ # trailing comment must not break parsing
    - assets/fonts/OFL-InterTight.txt
  fonts:
    - family: InterTight
      fonts:
        - asset: assets/fonts/InterTight-Variable.ttf

flutter_launcher_icons:
  android: true
  image_path: "assets/icons/logo.png"
'''


class ManifestTest(unittest.TestCase):
    def test_reads_directory_file_and_font_entries(self):
        declared = declared_assets(PUBSPEC)
        self.assertIn('assets', declared)
        self.assertIn('assets/images', declared)
        self.assertIn('assets/fonts/OFL-InterTight.txt', declared)
        self.assertIn('assets/fonts/InterTight-Variable.ttf', declared)

    def test_ignores_other_sections(self):
        self.assertEqual(
            declared_assets('flutter_launcher_icons:\n  android: true\n'), set()
        )

    def test_handles_a_manifest_without_assets(self):
        self.assertEqual(
            declared_assets('name: x\nflutter:\n  uses-material-design: true\n'),
            set(),
        )

    def test_the_asset_list_is_removed_from_the_usage_text(self):
        stripped = manifest_without_asset_list(PUBSPEC)
        self.assertNotIn('- assets/images/', stripped)
        self.assertIn('assets/icons/logo.png', stripped, 'other sections stay')
        self.assertIn('fonts:', stripped)


class DeclarationCoverageTest(unittest.TestCase):
    def test_directory_entry_covers_its_files(self):
        self.assertEqual(
            undeclared_assets({'assets/images/cover.jpg': 10}, declared_assets(PUBSPEC)),
            [],
        )

    def test_a_missing_manifest_entry_is_reported(self):
        bundled = {'assets/images/sffinks.png': 1153433}
        pubspec = 'flutter:\n  assets:\n    - assets/icons/\n'
        self.assertEqual(
            undeclared_assets(bundled, declared_assets(pubspec)),
            ['assets/images/sffinks.png'],
        )


class ReferenceTest(unittest.TestCase):
    def _lib(self, folder: pathlib.Path, source: str) -> pathlib.Path:
        lib = folder / 'lib'
        lib.mkdir()
        (lib / 'widget.dart').write_text(source, encoding='utf-8')
        return lib

    def test_a_path_named_in_a_source_is_referenced(self):
        with tempfile.TemporaryDirectory() as temp:
            lib = self._lib(
                pathlib.Path(temp),
                "const cover = 'assets/images/cover.jpg';",
            )
            usage = source_usage_text(lib, PUBSPEC)
        self.assertEqual(unreferenced_assets({'assets/images/cover.jpg': 1}, usage), [])

    def test_a_basename_named_in_a_source_is_referenced(self):
        with tempfile.TemporaryDirectory() as temp:
            lib = self._lib(pathlib.Path(temp), 'const name = "cover.jpg";')
            usage = source_usage_text(lib, PUBSPEC)
        self.assertEqual(unreferenced_assets({'assets/images/cover.jpg': 1}, usage), [])

    def test_a_font_declaration_counts_as_usage(self):
        with tempfile.TemporaryDirectory() as temp:
            lib = self._lib(pathlib.Path(temp), '')
            usage = source_usage_text(lib, PUBSPEC)
        self.assertEqual(
            unreferenced_assets({'assets/fonts/InterTight-Variable.ttf': 1}, usage),
            [],
        )

    def test_the_asset_list_alone_does_not_count_as_usage(self):
        # Declared only because `- assets/` is listed; nothing names the file.
        with tempfile.TemporaryDirectory() as temp:
            lib = self._lib(pathlib.Path(temp), "const cover = 'other.jpg';")
            usage = source_usage_text(lib, PUBSPEC)
        self.assertEqual(
            unreferenced_assets({'assets/images/sffinks.png': 1}, usage),
            ['assets/images/sffinks.png'],
        )

    def test_license_texts_are_expected_to_have_no_reference(self):
        with tempfile.TemporaryDirectory() as temp:
            lib = self._lib(pathlib.Path(temp), '')
            usage = source_usage_text(lib, PUBSPEC)
        self.assertEqual(
            unreferenced_assets({'assets/fonts/OFL-InterTight.txt': 1}, usage),
            [],
        )


class SizeTest(unittest.TestCase):
    def test_budget_is_exclusive(self):
        bundled = {
            'assets/a.png': DEFAULT_BUDGET_BYTES,
            'assets/b.png': DEFAULT_BUDGET_BYTES + 1,
        }
        oversized = oversized_assets(bundled, DEFAULT_BUDGET_BYTES)
        self.assertEqual(len(oversized), 1)
        self.assertIn('assets/b.png', oversized[0])

    def test_buckets_are_the_ones_a_size_discussion_uses(self):
        self.assertEqual(bucket_of('lib/arm64-v8a/libapp.so'), 'lib/arm64-v8a')
        self.assertEqual(
            bucket_of('assets/flutter_assets/assets/icons/logo.png'),
            'assets (declared)',
        )
        self.assertEqual(
            bucket_of('assets/flutter_assets/FontManifest.json'),
            'assets (engine: manifests, shaders, fonts)',
        )
        self.assertEqual(bucket_of('classes.dex'), 'dex')
        self.assertEqual(bucket_of('META-INF/CERT.RSA'), 'META-INF/ (signature)')
        self.assertEqual(bucket_of('AndroidManifest.xml'), 'other')

    def test_report_lists_buckets_and_largest_entries(self):
        report = size_report(
            [('lib/arm64-v8a/libapp.so', 2048), ('classes.dex', 1024)], top=1
        )
        self.assertIn('lib/arm64-v8a', report)
        self.assertIn('dex', report)
        self.assertEqual(report.count('libapp.so'), 1, 'top entries honour --top')

    def test_the_asset_table_flags_every_problem(self):
        bundled = {'assets/images/big.png': DEFAULT_BUDGET_BYTES + 1}
        table = asset_table(bundled, usage='', budget_bytes=DEFAULT_BUDGET_BYTES)
        self.assertIn('NOT REFERENCED', table)
        self.assertIn('OVER BUDGET', table)


class AnalyzeTest(unittest.TestCase):
    def _apk(self, folder: pathlib.Path, files: dict[str, int]) -> pathlib.Path:
        apk = folder / 'app-release.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'\x00' * 8)
            for name, size in files.items():
                archive.writestr(name, b'\x00' * size)
        return apk

    def _lib(self, folder: pathlib.Path, source: str) -> pathlib.Path:
        lib = folder / 'lib'
        lib.mkdir()
        (lib / 'cover.dart').write_text(source, encoding='utf-8')
        return lib

    def test_a_matching_build_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp)
            lib = self._lib(folder, "const c = 'assets/icons/logo.png';")
            apk = self._apk(
                folder,
                {'assets/flutter_assets/assets/icons/logo.png': 32},
            )
            analysis = analyze(apk, PUBSPEC, lib_root=lib)
        self.assertEqual(analysis.failures, [])
        self.assertIn('OK: every bundled asset is declared, referenced', analysis.report)

    def test_an_unreferenced_oversized_asset_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp)
            lib = self._lib(folder, "const c = 'assets/icons/logo.png';")
            apk = self._apk(
                folder,
                {
                    'assets/flutter_assets/assets/icons/logo.png': 32,
                    'assets/flutter_assets/assets/images/sffinks.png': DEFAULT_BUDGET_BYTES
                    + 1,
                },
            )
            analysis = analyze(apk, PUBSPEC, lib_root=lib)
        joined = '\n'.join(analysis.failures)
        self.assertIn('referenced nowhere', joined)
        self.assertIn('budget', joined)
        self.assertIn('sffinks.png', joined)

    def test_an_apk_without_assets_fails_instead_of_passing_vacuously(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp)
            lib = self._lib(folder, '')
            analysis = analyze(self._apk(folder, {}), PUBSPEC, lib_root=lib)
        self.assertEqual(len(analysis.failures), 1)
        self.assertIn('no bundled assets found', analysis.failures[0])

    def test_the_reference_scan_can_be_skipped(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp)
            apk = self._apk(
                folder, {'assets/flutter_assets/assets/images/orphan.png': 8}
            )
            analysis = analyze(apk, PUBSPEC)
        self.assertEqual(analysis.failures, [])
        self.assertIn('Reference scan skipped', analysis.report)

    def test_apk_entries_ignores_directories(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = pathlib.Path(temp)
            apk = folder / 'app.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('assets/', b'')
                archive.writestr('assets/file.txt', b'x')
            names = [name for name, _ in apk_entries(apk)]
        self.assertEqual(names, ['assets/file.txt'])

    def test_bundled_assets_are_keyed_by_repository_path(self):
        entries = [
            ('assets/flutter_assets/assets/icons/logo.png', 4),
            ('classes.dex', 8),
        ]
        self.assertEqual(bundled_assets(entries), {'assets/icons/logo.png': 4})


if __name__ == '__main__':
    unittest.main()
