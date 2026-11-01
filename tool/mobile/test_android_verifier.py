"""Exercise the real APK gate against fake SDK output, not real signatures."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERIFY = ROOT / 'tool/mobile/verify_android_package.sh'


class AndroidVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        tools = self.root / 'android/build-tools/36.0.0'
        tools.mkdir(parents=True)
        ndk = self.root / 'android/ndk/27/toolchains/llvm/prebuilt/linux-x86_64/bin'
        ndk.mkdir(parents=True)
        self.write_tool(tools / 'apksigner', 'cat "$FIXTURE_CERT"')
        self.write_tool(tools / 'aapt', '''case "$2" in
  badging) cat "$FIXTURE_BADGING" ;;
  permissions) cat "$FIXTURE_PERMISSIONS" ;;
  xmltree) cat "$FIXTURE_MANIFEST" ;;
  *) exit 1 ;;
esac''')
        self.write_tool(tools / 'zipalign', 'exit "${FAIL_ALIGNMENT:-0}"')
        self.write_tool(ndk / 'llvm-readelf', "echo '  LOAD 0x0 0x0 0x0 0x0 0x0 R 0x4000'")
        self.cert = self.root / 'cert'
        self.badging = self.root / 'badging'
        self.permissions = self.root / 'permissions'
        self.manifest = self.root / 'manifest'
        self.cert.write_text('Signer #1 certificate DN: CN=Owner Fixture\n'
                             f'Signer #1 certificate SHA-256 digest: {"a" * 64}\n')
        self.badging.write_text("package: name='com.example.belog' versionCode='8' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\n")
        self.permissions.write_text("uses-permission: name='android.permission.INTERNET'\n"
                                    "uses-permission: name='android.permission.ACCESS_NETWORK_STATE'\n")
        self.manifest.write_text('E: manifest\n')
        self.apk = self.root / 'test.apk'
        self.make_apk()
        self.env = {**os.environ, 'ANDROID_HOME': str(self.root / 'android'),
                    'RUNNER_TEMP': str(self.root), 'FIXTURE_CERT': str(self.cert),
                    'FIXTURE_BADGING': str(self.badging), 'FIXTURE_PERMISSIONS': str(self.permissions),
                    'FIXTURE_MANIFEST': str(self.manifest)}

    @staticmethod
    def write_tool(path, body):
        path.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + body + '\n')
        path.chmod(0o755)

    def make_apk(self, *, include_32=True):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            archive.writestr('lib/arm64-v8a/libflutter.so', b'fake-elf')
            if include_32:
                archive.writestr('lib/armeabi-v7a/libflutter.so', b'fake-elf')

    def invoke(self, mode='personal', cert='a' * 64, **env):
        return subprocess.run(['bash', str(VERIFY), str(self.apk), '1.2.3', '8', mode, cert],
                              cwd=ROOT, env={**self.env, **env}, text=True, capture_output=True)

    def test_personal_package_runs_signature_manifest_and_alignment_gates(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('16 KiB compatible', result.stdout)
        self.assertIn('required network permissions verified', result.stdout)
        self.assertNotEqual(self.invoke(cert='b' * 64).returncode, 0)
        self.assertNotEqual(self.invoke(FAIL_ALIGNMENT='1').returncode, 0)

    def test_rejects_missing_permissions_wrong_abi_and_insecure_release(self):
        self.permissions.write_text("uses-permission: name='android.permission.INTERNET'\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ACCESS_NETWORK_STATE', result.stdout + result.stderr)
        self.permissions.write_text("uses-permission: name='android.permission.INTERNET'\n"
                                    "uses-permission: name='android.permission.ACCESS_NETWORK_STATE'\n")
        self.manifest.write_text('A: android:usesCleartextTraffic(0x010104ec)=(type 0x12)0xffffffff\n')
        self.assertNotEqual(self.invoke().returncode, 0)
        self.manifest.write_text('E: manifest\n')
        self.badging.write_text("package: name='com.example.belog' versionCode='8' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\napplication-debuggable\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.badging.write_text("package: name='com.example.belog' versionCode='8' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\n")
        self.make_apk(include_32=False)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('armeabi-v7a', result.stdout + result.stderr)

    def test_debug_build_is_explicitly_debuggable(self):
        self.assertNotEqual(self.invoke(mode='debug', cert='-').returncode, 0)
        self.badging.write_text("package: name='com.example.belog' versionCode='8' versionName='1.2.3'\nuses-permission: name='android.permission.INTERNET'\napplication-debuggable\n")
        self.assertEqual(self.invoke(mode='debug', cert='-').returncode, 0)


if __name__ == '__main__':
    unittest.main()
