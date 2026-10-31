import plistlib
import re
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


class DebugNetworkPolicyTests(unittest.TestCase):
    def test_ios_debug_only_http_exception_and_plist_parity(self):
        with (ROOT / 'ios/Runner/Info.plist').open('rb') as f:
            release = plistlib.load(f)
        with (ROOT / 'ios/Runner/Info-Debug.plist').open('rb') as f:
            debug = plistlib.load(f)
        self.assertNotIn('NSAppTransportSecurity', release)
        self.assertEqual(debug.pop('NSAppTransportSecurity'), {'NSAllowsArbitraryLoads': True})
        self.assertEqual(debug, release, 'Keep the debug plist in sync with the release plist')
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(project.count('INFOPLIST_FILE = Runner/Info-Debug.plist;'), 1)
        self.assertEqual(project.count('INFOPLIST_FILE = Runner/Info.plist;'), 2)
        debug_block = project.split('baseConfigurationReference = 9740EEB21CF90195004384FC /* Debug.xcconfig */;')[1].split('name = Debug;')[0]
        self.assertIn('INFOPLIST_FILE = Runner/Info-Debug.plist;', debug_block)

    def test_android_debug_only_http_exception(self):
        android_name = '{http://schemas.android.com/apk/res/android}usesCleartextTraffic'
        root = ROOT / 'android/app/src'
        debug = ET.parse(root / 'debug/AndroidManifest.xml').getroot().find('application')
        self.assertEqual(debug.get(android_name), 'true')
        for variant in ('main', 'profile'):
            app = ET.parse(root / variant / 'AndroidManifest.xml').getroot().find('application')
            self.assertTrue(app is None or app.get(android_name) != 'true')

    def test_only_public_example_is_tracked_by_config_ignore_rules(self):
        ignore = (ROOT / '.gitignore').read_text()
        self.assertIn('/env.json', ignore)
        self.assertIn('/env.*.json', ignore)
        self.assertIn('!/env.example.json', ignore)

    def test_presentation_and_domain_do_not_import_feature_data(self):
        feature_root = ROOT / 'lib/features'
        forbidden = re.compile(r'''(?:import|export)\s+['\"](?:package:belog/features/[^'\"]*/data/|(?:\.\./)+data/)''')
        framework = re.compile(r'''(?:import|export)\s+['\"]package:(?:flutter|drift|isar_community)/''')
        for feature in feature_root.iterdir():
            for layer in ('presentation', 'domain'):
                for path in (feature / layer).rglob('*.dart'):
                    source = path.read_text(encoding='utf-8')
                    self.assertIsNone(forbidden.search(source), f'{path} depends on feature data')
                    if layer == 'domain':
                        self.assertIsNone(framework.search(source), f'{path} depends on UI or database frameworks')
