import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


class LegacyApkTest(unittest.TestCase):
    def test_accepts_only_exact_rebuilt_libraries(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / 'jni' / 'arm64-v8a' / 'libisar.so'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'rebuilt')
            apk = root / 'app.apk'
            script = Path(__file__).with_name('check_legacy_apk.py')
            def check(contents):
                with zipfile.ZipFile(apk, 'w') as out:
                    for name, data in contents.items():
                        out.writestr(name, data)
                return subprocess.run([sys.executable, str(script), str(apk), str(root / 'jni')], capture_output=True)
            self.assertEqual(check({'lib/arm64-v8a/libflutter.so': b'flutter', 'lib/arm64-v8a/libisar.so': b'rebuilt'}).returncode, 0)
            self.assertNotEqual(check({'lib/arm64-v8a/libflutter.so': b'flutter', 'lib/arm64-v8a/libisar.so': b'old'}).returncode, 0)
            self.assertNotEqual(check({'lib/x86_64/libflutter.so': b'flutter', 'lib/x86_64/libisar.so': b'rebuilt'}).returncode, 0)
            self.assertNotEqual(check({}).returncode, 0)


if __name__ == '__main__':
    unittest.main()
