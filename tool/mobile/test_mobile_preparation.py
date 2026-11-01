import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'tool/mobile/prepare_config.py'
SIGNING = ROOT / 'tool/mobile/prepare_android_signing.py'


class MobilePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('name: belog\nversion: 1.2.3+7\n')
        self.env = {
            **os.environ,
            'GITHUB_EVENT_NAME': 'workflow_dispatch',
            'GITHUB_REF': 'refs/heads/main',
            'GITHUB_RUN_NUMBER': '8',
            'GITHUB_OUTPUT': str(self.root / 'output'),
            'PUBLIC_API_ORIGIN': 'https://api.real-service.dev',
            'PUBLIC_WEB_ORIGIN': 'https://web.real-service.dev',
            'INPUT_TARGET': 'both',
            'INPUT_ANDROID_MODE': 'personal',
            'INPUT_BUILD_NUMBER': '',
        }
        self.config = self.root / 'config.json'

    def invoke(self, script, output, **env):
        return subprocess.run([sys.executable, str(script), str(output)], cwd=self.root,
                              env={**self.env, **env}, text=True, capture_output=True)

    def test_manual_public_config_and_version_are_written_privately(self):
        result = self.invoke(CONFIG, self.config)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.config.read_text()), {
            'API_BASE_URL': self.env['PUBLIC_API_ORIGIN'],
            'WEB_BASE_URL': self.env['PUBLIC_WEB_ORIGIN'],
        })
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        self.assertIn('build_name=1.2.3\nbuild_number=8', (self.root / 'output').read_text())
        self.assertNotIn(self.env['PUBLIC_API_ORIGIN'], result.stdout + result.stderr)

    def test_request_must_be_from_main_and_use_non_placeholder_https_origins(self):
        cases = (
            {'GITHUB_REF': 'refs/heads/feature'},
            {'PUBLIC_API_ORIGIN': ''},
            {'PUBLIC_API_ORIGIN': 'https://example.invalid'},
            {'PUBLIC_API_ORIGIN': 'http://api.real-service.dev'},
            {'PUBLIC_API_ORIGIN': 'https://localhost.'},
            {'PUBLIC_API_ORIGIN': 'https://127.0.0.1'},
            {'PUBLIC_API_ORIGIN': 'https://192.168.1.5'},
            {'PUBLIC_API_ORIGIN': 'https://user:private-password@api.real-service.dev'},
            {'PUBLIC_API_ORIGIN': 'https://api.real-service.dev/api/v1'},
            {'PUBLIC_API_ORIGIN': 'https://api.real-service.dev?token=private-password'},
            {'PUBLIC_WEB_ORIGIN': 'https://example.com'},
            {'INPUT_TARGET': 'unknown'},
            {'INPUT_ANDROID_MODE': 'automatic'},
            {'INPUT_BUILD_NUMBER': '0'},
            {'INPUT_BUILD_NUMBER': '6'},
            {'INPUT_BUILD_NUMBER': '2100000001'},
        )
        for case in cases:
            with self.subTest(case=case):
                result = self.invoke(CONFIG, self.config, **case)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.config.exists())
                self.assertNotIn('private-password', result.stdout + result.stderr)

    def test_pull_request_always_uses_disconnected_fixture_and_no_owner_input(self):
        result = self.invoke(CONFIG, self.config, GITHUB_EVENT_NAME='pull_request',
                             GITHUB_REF='refs/pull/1/merge',
                             PUBLIC_API_ORIGIN='https://should-not-be-used.dev',
                             INPUT_BUILD_NUMBER='999')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.config.read_text())['API_BASE_URL'], 'https://127.0.0.1')
        self.assertIn('build_number=8', (self.root / 'output').read_text())

    def test_never_overwrites_existing_config(self):
        self.config.write_text('preserve')
        result = self.invoke(CONFIG, self.config)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), 'preserve')

    def test_signing_is_private_and_fails_closed_without_echoing_values(self):
        keystore = self.root / 'test.keystore'
        sign_env = {
            'ANDROID_APPLICATION_ID_APPROVED': 'com.example.belog',
            'ANDROID_RELEASE_CERT_SHA256': 'a' * 64,
            'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'fixture-key').decode(),
            'ANDROID_KEYSTORE_PASSWORD': 'fixture-secret-password',
            'ANDROID_KEY_ALIAS': 'fixture-alias',
            'ANDROID_KEY_PASSWORD': 'fixture-secret-password',
        }
        for overrides in (
            {'ANDROID_APPLICATION_ID_APPROVED': ''},
            {'ANDROID_RELEASE_CERT_SHA256': 'wrong'},
            {'ANDROID_KEY_PASSWORD': ''},
            {'ANDROID_KEY_ALIAS': 'androiddebugkey'},
            {'ANDROID_KEYSTORE_BASE64': 'not-base64!'},
        ):
            with self.subTest(overrides=overrides):
                result = self.invoke(SIGNING, keystore, **{**sign_env, **overrides})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(keystore.exists())
                self.assertNotIn('fixture-secret-password', result.stdout + result.stderr)
                self.assertNotIn('not-base64!', result.stdout + result.stderr)
        result = self.invoke(SIGNING, keystore, **sign_env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(keystore.read_bytes(), b'fixture-key')
        self.assertEqual(keystore.stat().st_mode & 0o777, 0o600)
        result = self.invoke(SIGNING, keystore, **sign_env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(keystore.read_bytes(), b'fixture-key')


if __name__ == '__main__':
    unittest.main()
