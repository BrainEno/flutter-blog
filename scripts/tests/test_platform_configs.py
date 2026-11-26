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

    def test_android_private_data_backup_is_disabled_and_explicitly_excluded(self):
        android_name = '{http://schemas.android.com/apk/res/android}'
        manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        application = manifest.find('application')
        self.assertIsNotNone(application)
        self.assertEqual(application.get(f'{android_name}allowBackup'), 'false')
        self.assertEqual(application.get(f'{android_name}fullBackupContent'), '@xml/backup_rules')
        self.assertEqual(application.get(f'{android_name}dataExtractionRules'), '@xml/data_extraction_rules')

        resources = ROOT / 'android/app/src/main/res/xml'
        backup = ET.parse(resources / 'backup_rules.xml').getroot()
        self.assertEqual(backup.tag, 'full-backup-content')
        expected_domains = {'root', 'file', 'database', 'sharedpref', 'external'}
        self.assertEqual(
            {(node.get('domain'), node.get('path')) for node in backup.findall('exclude')},
            {(domain, '.') for domain in expected_domains},
        )

        extraction = ET.parse(resources / 'data_extraction_rules.xml').getroot()
        self.assertEqual(extraction.tag, 'data-extraction-rules')
        for section_name in ('cloud-backup', 'device-transfer'):
            section = extraction.find(section_name)
            self.assertIsNotNone(section, section_name)
            self.assertEqual(
                {(node.get('domain'), node.get('path')) for node in section.findall('exclude')},
                {(domain, '.') for domain in expected_domains},
            )
        self.assertEqual(
            extraction.find('cloud-backup').get('disableIfNoEncryptionCapabilities'),
            'true',
        )

    def test_permissions_match_actual_mobile_capabilities(self):
        android_name = '{http://schemas.android.com/apk/res/android}name'
        root = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        permissions = {element.get(android_name) for element in root.findall('uses-permission')}
        self.assertTrue({'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'} <= permissions)
        # Gallery selection is delegated to the system picker. Do not silently
        # grant access to unrelated sensors or the entire media library.
        self.assertFalse(permissions & {'android.permission.CAMERA', 'android.permission.RECORD_AUDIO',
                                       'android.permission.ACCESS_FINE_LOCATION', 'android.permission.READ_EXTERNAL_STORAGE',
                                       'android.permission.READ_MEDIA_IMAGES'})
        with (ROOT / 'ios/Runner/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        for key in ('NSPhotoLibraryUsageDescription', 'NSCameraUsageDescription'):
            self.assertTrue(info.get(key))
        for locale in ('en', 'zh-Hans'):
            strings = (ROOT / f'ios/Runner/{locale}.lproj/InfoPlist.strings').read_text()
            self.assertIn('NSPhotoLibraryUsageDescription', strings)
            self.assertIn('NSCameraUsageDescription', strings)

    def test_only_public_example_is_tracked_by_config_ignore_rules(self):
        ignore = (ROOT / '.gitignore').read_text()
        self.assertIn('/env.json', ignore)
        self.assertIn('/env.*.json', ignore)
        self.assertIn('!/env.example.json', ignore)

    def test_presentation_and_domain_do_not_import_feature_data(self):
        feature_root = ROOT / 'lib/features'
        forbidden = re.compile(r'''(?:import|export)\s+['\"](?:package:belog/features/[^'\"]*/data/|(?:\.\./)+data/)''')
        framework = re.compile(r'''(?:import|export)\s+['\"]package:(?:flutter|drift)/''')
        for feature in feature_root.iterdir():
            for layer in ('presentation', 'domain'):
                for path in (feature / layer).rglob('*.dart'):
                    source = path.read_text(encoding='utf-8')
                    self.assertIsNone(forbidden.search(source), f'{path} depends on feature data')
                    if layer == 'domain':
                        self.assertIsNone(framework.search(source), f'{path} depends on UI or database frameworks')


class ArticleDeepLinkSurfaceTests(unittest.TestCase):
    """The OS side of #367: what the platform configs are allowed to claim.

    A deep-link declaration that is wider than the app can handle is a bug with
    no visible symptom - Android verification fails silently, iOS sends the
    user to Safari - so the narrow surface is pinned here rather than trusted
    to docs. Adding a hosted association is the owner's call (see
    docs/deep-links.md); when it happens, these expectations move with it.
    """

    ANDROID_NS = '{http://schemas.android.com/apk/res/android}'

    def _android_view_data(self):
        root = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        android = self.ANDROID_NS
        rows = []
        for filter_ in root.find('application').findall('.//intent-filter'):
            actions = {el.get(f'{android}name') for el in filter_.findall('action')}
            if 'android.intent.action.VIEW' not in actions:
                continue
            for data in filter_.findall('data'):
                rows.append(
                    {key[len(android):]: value for key, value in data.attrib.items() if key.startswith(android)}
                )
        return rows

    def test_android_opens_only_the_custom_scheme_for_the_article_host(self):
        rows = self._android_view_data()
        self.assertEqual(rows, [{'scheme': 'nowave', 'host': 'article'}], 'Android must not declare a link the app cannot resolve')
        manifest = (ROOT / 'android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
        # autoVerify without a served assetlinks.json is a broken verification,
        # and a wildcard host would route every site's links into the app.
        self.assertNotIn('autoVerify', manifest)
        self.assertNotIn('"*"', manifest)
        for row in rows:
            self.assertFalse({'pathPrefix', 'pathPattern', 'path'} & row.keys())
            self.assertNotIn('*', ''.join(row.values()))

    def test_ios_registers_the_scheme_and_no_associated_domains(self):
        for name in ('ios/Runner/Info.plist', 'ios/Runner/Info-Debug.plist'):
            with (ROOT / name).open('rb') as stream:
                info = plistlib.load(stream)
            self.assertEqual(
                info.get('CFBundleURLTypes'),
                [{'CFBundleTypeRole': 'Editor', 'CFBundleURLName': 'com.nodeman24.nowave.article', 'CFBundleURLSchemes': ['nowave']}],
                f'{name} URL types drifted from the custom scheme',
            )
            self.assertNotIn('com.apple.developer.associated-domains', info, f'{name} claims Universal Links the repo cannot verify')
        self.assertEqual(sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'ios').rglob('*.entitlements')), [])

    def test_platform_configs_match_the_dart_constants(self):
        source = (ROOT / 'lib/core/utils/article_deep_link.dart').read_text(encoding='utf-8')
        const = re.compile(r"const String (kArticleDeepLink\w+) = '([^']*)';")
        found = dict(const.findall(source))
        self.assertEqual(
            (found.get('kArticleDeepLinkScheme'), found.get('kArticleDeepLinkHost')),
            ('nowave', 'article'),
            'article_deep_link.dart no longer defines the constants these configs are read against',
        )
        rows = self._android_view_data()
        self.assertEqual(
            [(row.get('scheme'), row.get('host')) for row in rows],
            [(found['kArticleDeepLinkScheme'], found['kArticleDeepLinkHost'])],
            'renaming the scheme or host in Dart without the manifest leaves deep links dead on arrival',
        )
        with (ROOT / 'ios/Runner/Info.plist').open('rb') as stream:
            schemes = plistlib.load(stream)['CFBundleURLTypes'][0]['CFBundleURLSchemes']
        self.assertEqual(schemes, [found['kArticleDeepLinkScheme']])


if __name__ == '__main__':
    unittest.main()
