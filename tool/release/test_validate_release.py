import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from validate_release import validate_public_config, validate_version


def jwt(role):
    payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
    return f"header.{payload}.signature"


class ReleaseValidationTests(unittest.TestCase):
    def test_apk_verifier_output_and_security_cases(self):
        script = Path(__file__).with_name("test_verify_apk.sh").resolve()
        result = subprocess.run(["bash", str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_matching_tag(self):
        self.assertEqual(validate_version("v1.2.3+42", "name: belog\nversion: 1.2.3+42\n"), ("1.2.3", "42"))

    def test_invalid_or_mismatched_versions(self):
        for tag in ("v1.2.3", "v01.2.3+42", "v1.2.3+0", "v1.2.3+2100000001", "v1.2.4+42", "v1.2.3+42\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate_version(tag, "version: 1.2.3+42\n")

    def test_public_key_only(self):
        for key in ("sb_publishable_abc", jwt("anon")):
            validate_public_config("https://project.supabase.co", key)
        for key in ("sb_secret_abc", jwt("service_role"), "not-a-key", ""):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_public_config("https://project.supabase.co", key)

    def test_real_https_url_required(self):
        for url in ("https://example.invalid", "http://project.supabase.co", "https://localhost", "https://user:pass@host.example", "https://site.test", "https://127.0.0.1", "https://example.com"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_public_config(url, "sb_publishable_abc")

    def test_main_fails_closed_and_writes_private_fixture(self):
        script = Path(__file__).with_name("validate_release.py").resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("version: 1.2.3+42\n")
            env = {
                "GITHUB_REF_NAME": "v1.2.3+42",
                "GITHUB_OUTPUT": str(root / "output"),
                "RUNNER_TEMP": str(root),
                "ANDROID_APPLICATION_ID_APPROVED": "com.example.belog",
                "ANDROID_RELEASE_CERT_SHA256": "a" * 64,
                "ANDROID_KEYSTORE_BASE64": "test-only-keystore",
                "ANDROID_KEYSTORE_PASSWORD": "test-only-store-password",
                "ANDROID_KEY_ALIAS": "test-only-alias",
                "ANDROID_KEY_PASSWORD": "test-only-key-password",
                "SUPABASE_URL": "https://project.supabase.co",
                "SUPABASE_KEY": "sb_publishable_test_only",
            }
            for missing in ("ANDROID_KEYSTORE_BASE64", "ANDROID_KEY_PASSWORD", "ANDROID_APPLICATION_ID_APPROVED", "ANDROID_RELEASE_CERT_SHA256", "SUPABASE_KEY"):
                result = subprocess.run([sys.executable, str(script)], cwd=root, env={**env, missing: ""}, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, missing)
                self.assertNotIn("test-only", result.stderr)
                self.assertFalse((root / "belog-release-env.json").exists())
            result = subprocess.run([sys.executable, str(script)], cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = root / "belog-release-env.json"
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(config.read_text())["SUPABASE_KEY"], env["SUPABASE_KEY"])
            self.assertIn("build_number=42", (root / "output").read_text())


if __name__ == "__main__":
    unittest.main()
