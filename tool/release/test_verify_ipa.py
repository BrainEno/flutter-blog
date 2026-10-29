import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

BUNDLE_ID = 'com.nodeman24.belog'
BUILD_NAME = '1.2.3'
BUILD_NUMBER = '42'

INFO = {
    'CFBundleIdentifier': BUNDLE_ID,
    'CFBundleShortVersionString': BUILD_NAME,
    'CFBundleVersion': BUILD_NUMBER,
    'CFBundleExecutable': 'Runner',
    'CFBundlePackageType': 'APPL',
    'LSRequiresIPhoneOS': True,
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
            self.assertIn('Cannot open IPA', result.stdout)


if __name__ == '__main__':
    unittest.main()
