import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

BUNDLE_ID = 'com.nodeman24.nowave'
BUILD_NAME = '1.2.3'
BUILD_NUMBER = '42'

INFO = {
    'CFBundleIdentifier': BUNDLE_ID,
    'CFBundleShortVersionString': BUILD_NAME,
    'CFBundleVersion': BUILD_NUMBER,
    'CFBundleExecutable': 'Runner',
    'CFBundlePackageType': 'APPL',
    'LSRequiresIPhoneOS': True,
    'CFBundleSupportedPlatforms': ['iPhoneOS'],
    'NSPhotoLibraryUsageDescription': 'Select a cover photo',
    'NSCameraUsageDescription': 'Take a photo',
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
}


def make_ipa(
    path: Path,
    *,
    entries: dict | None = None,
    info: dict | None = None,
) -> None:
    """Write a fake IPA with the default Flutter app layout."""
    content = entries if entries is not None else {
        'Payload/Runner.app/Info.plist': plistlib.dumps(
            INFO if info is None else info,
        ),
        'Payload/Runner.app/Runner': b'Mach-O executable',
        'Payload/Runner.app/Frameworks/Flutter.framework/Flutter': b'engine',
        'Payload/Runner.app/Frameworks/App.framework/App': b'app',
        'Payload/Runner.app/en.lproj/InfoPlist.strings': b'localized-en',
        'Payload/Runner.app/zh-Hans.lproj/InfoPlist.strings': b'localized-zh',
    }
    with zipfile.ZipFile(path, 'w') as archive:
        for name, data in content.items():
            archive.writestr(name, data)


class VerifyIpaTest(unittest.TestCase):
    def run_verify(self, path: Path):
        script = Path(__file__).with_name('verify_ipa.py')
        return subprocess.run(
            [
                sys.executable,
                str(script),
                str(path),
                BUNDLE_ID,
                BUILD_NAME,
                BUILD_NUMBER,
            ],
            capture_output=True,
            text=True,
        )

    def test_valid_ipa_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa)
            result = self.run_verify(ipa)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('IPA structure, identity and version verified.', result.stdout)
            self.assertIn(f'CFBundleIdentifier: {BUNDLE_ID}', result.stdout)

    def test_rejects_wrong_top_level_layout(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Runner.app/Info.plist', plistlib.dumps(INFO))
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('only a Payload/ directory', result.stdout + result.stderr)

    def test_rejects_second_app_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr(
                    'Payload/Runner.app/Info.plist', plistlib.dumps(INFO),
                )
                archive.writestr('Payload/Other.app/Info.plist', b'x')
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('exactly Runner.app', result.stdout + result.stderr)

    def test_rejects_missing_flutter_frameworks(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa, entries={
                'Payload/Runner.app/Info.plist': plistlib.dumps(INFO),
                'Payload/Runner.app/Runner': b'Mach-O executable',
            })
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                'Missing required entry: Payload/Runner.app/Frameworks/'
                'Flutter.framework/Flutter',
                result.stdout + result.stderr,
            )

    def test_rejects_wrong_bundle_id(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa, info={**INFO, 'CFBundleIdentifier': 'com.wrong.app'})
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('CFBundleIdentifier', result.stdout + result.stderr)

    def test_rejects_wrong_version(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa, info={**INFO, 'CFBundleShortVersionString': '9.9.9'})
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                'CFBundleShortVersionString', result.stdout + result.stderr,
            )

    def test_rejects_missing_executable(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa, entries={
                'Payload/Runner.app/Info.plist': plistlib.dumps(INFO),
                'Payload/Runner.app/Frameworks/Flutter.framework/Flutter': b'engine',
                'Payload/Runner.app/Frameworks/App.framework/App': b'app',
            })
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                'Missing required entry: Payload/Runner.app/Runner',
                result.stdout + result.stderr,
            )

    def test_rejects_not_a_zip(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            ipa.write_bytes(b'this is not a zip file')
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('IPA verification failed', result.stdout + result.stderr)

    def test_rejects_simulator_and_missing_privacy_description(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            for info, message in (
                ({**INFO, 'CFBundleSupportedPlatforms': ['iPhoneSimulator']}, 'iPhoneOS device'),
                ({**INFO, 'NSPhotoLibraryUsageDescription': ''}, 'NSPhotoLibraryUsageDescription'),
                ({**INFO, 'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True}}, 'cleartext'),
            ):
                with self.subTest(message=message):
                    make_ipa(ipa, info=info)
                    result = self.run_verify(ipa)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stdout + result.stderr)

    def test_rejects_traversal_duplicates_profiles_and_extensions(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            for extra, message in (
                ('../../escape', 'Unsafe IPA entry'),
                ('Payload/Runner.app/embedded.mobileprovision', 'provisioning profile'),
                ('Payload/Runner.app/PlugIns/Widget.appex/Info.plist', 'App extensions'),
            ):
                with self.subTest(extra=extra):
                    make_ipa(ipa)
                    with zipfile.ZipFile(ipa, 'a') as archive:
                        archive.writestr(extra, b'data')
                    result = self.run_verify(ipa)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stdout + result.stderr)
            make_ipa(ipa)
            with zipfile.ZipFile(ipa, 'a') as archive:
                with self.assertWarns(UserWarning):
                    archive.writestr('Payload/Runner.app/Runner', b'duplicate')
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('duplicate', result.stdout + result.stderr)

    def test_rejects_symlink_escaping_the_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / 'app.ipa'
            make_ipa(ipa)
            link = zipfile.ZipInfo('Payload/Runner.app/escape')
            link.create_system = 3
            link.external_attr = (0o120777 << 16)
            with zipfile.ZipFile(ipa, 'a') as archive:
                archive.writestr(link, '../../../../outside')
            result = self.run_verify(ipa)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unsafe IPA symlink', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
