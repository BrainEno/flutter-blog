import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('validate_config', SCRIPTS / 'validate_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)
selector_spec = importlib.util.spec_from_file_location('select_ios_simulator', SCRIPTS / 'select_ios_simulator.py')
selector = importlib.util.module_from_spec(selector_spec)
selector_spec.loader.exec_module(selector)


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'env.json'

    def check(self, value, *, release=False, platform='ios'):
        self.path.write_text(json.dumps(value), encoding='utf-8')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            config.validate(self.path, platform=platform, release=release)
        return output.getvalue()

    def test_local_http_is_debug_only_and_warning_is_explicit(self):
        data = {'API_BASE_URL': 'http://10.0.2.2:8787', 'WEB_BASE_URL': ''}
        self.assertIn('unencrypted', self.check(data, platform='android'))
        with self.assertRaises(ValueError):
            self.check(data, release=True)

    def test_android_loopback_warning_and_https_release(self):
        warning = self.check({'API_BASE_URL': 'http://localhost:3000'}, platform='android')
        self.assertIn('10.0.2.2', warning)
        self.check({'API_BASE_URL': 'https://api.real-site.dev', 'WEB_BASE_URL': 'https://web.real-site.dev'}, release=True)

    def test_bad_urls_and_client_secrets_are_rejected_without_echoing_them(self):
        cases = [
            {'API_BASE_URL': 'https://your-nowave-api.example.com'},
            {'API_BASE_URL': 'https://api.invalid'},
            {'API_BASE_URL': 'https://user:badsecret@api.real.dev'},
            {'API_BASE_URL': 'https://api.real.dev/api/v1'},
            {'API_BASE_URL': 'https://api.real.dev?secret=badsecret'},
            {'API_BASE_URL': 'https://api.real.dev#fragment'},
            {'API_BASE_URL': 'https://api.real.dev:99999'},
            {'API_BASE_URL': 'https://api.real.dev', 'SECRET': 'badsecret'},
            {'API_BASE_URL': 'https://api.real.dev', 'WEB_BASE_URL': 'https://your-nowave-web.example.com'},
            {'API_BASE_URL': None},
            [],
        ]
        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(ValueError) as caught:
                    self.check(value)
                self.assertNotIn('badsecret', str(caught.exception))

    def test_duplicate_json_keys_fail(self):
        self.path.write_text('{"API_BASE_URL":"https://a.dev","API_BASE_URL":"https://b.dev"}')
        with self.assertRaises(ValueError):
            config.validate(self.path, platform='ios', release=False)


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.devices = {
            'com.apple.CoreSimulator.SimRuntime.iOS-17-5': [
                {'name': 'iPhone 15', 'udid': 'OLD', 'state': 'Booted', 'isAvailable': True},
            ],
            'com.apple.CoreSimulator.SimRuntime.iOS-18-1': [
                {'name': 'iPhone 16', 'udid': 'NEW', 'state': 'Shutdown', 'isAvailable': True},
                {'name': 'iPad Air', 'udid': 'IPAD', 'state': 'Shutdown', 'isAvailable': True},
            ],
        }

    def test_prefers_running_then_newest_runtime(self):
        self.assertEqual(selector.choose(self.devices, '')['udid'], 'OLD')
        self.devices['com.apple.CoreSimulator.SimRuntime.iOS-17-5'][0]['state'] = 'Shutdown'
        self.assertEqual(selector.choose(self.devices, '')['udid'], 'NEW')

    def test_explicit_udid_ipad_and_ambiguous_name(self):
        self.assertEqual(selector.choose(self.devices, 'IPAD')['udid'], 'IPAD')
        self.devices['com.apple.CoreSimulator.SimRuntime.iOS-17-5'][0]['name'] = 'iPhone 16'
        with self.assertRaises(ValueError):
            selector.choose(self.devices, 'iPhone 16')
        with self.assertRaises(ValueError):
            selector.choose(self.devices, 'DOES-NOT-EXIST')

    def test_no_available_phone_fails(self):
        with self.assertRaises(ValueError):
            selector.choose({'com.apple.CoreSimulator.SimRuntime.iOS-18-1': []}, '')
