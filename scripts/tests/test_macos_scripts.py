"""Control-flow tests with fake macOS tools; not Xcode/device/signing validation."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]

MOCK_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, shutil, sys, time, zipfile
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
log = pathlib.Path(os.environ['MOCK_LOG'])
with log.open('a') as stream:
    stream.write(json.dumps([name] + args) + '\n')
root = pathlib.Path(os.environ['MOCK_ROOT'])
if name == 'uname':
    print('Darwin')
elif name == 'xcodebuild':
    print('Xcode (mock)')
elif name == 'open':
    pass
elif name == 'xcrun':
    if args[:4] == ['simctl', 'list', 'devices', 'available']:
        print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-18-1': [
            {'name':'iPhone 16', 'udid':'SIM-123', 'state':os.environ.get('MOCK_SIM_STATE','Shutdown'), 'isAvailable':True}
        ]}}))
    elif args[:2] == ['simctl', 'bootstatus'] and os.environ.get('MOCK_SLOW_BOOT'):
        time.sleep(4)
    elif args[:2] not in (['simctl','boot'], ['simctl','bootstatus']):
        sys.exit(1)
elif name == 'codesign':
    if os.environ.get('MOCK_FAIL_CODESIGN'):
        sys.exit(3)
elif name == 'ditto':
    if args[:2] == ['-x', '-k']:
        with zipfile.ZipFile(args[2]) as z:
            z.extractall(args[3])
    else:
        shutil.copytree(args[0], args[1], dirs_exist_ok=True, symlinks=True)
elif name == 'flutter':
    if args == ['--version', '--machine']:
        print(json.dumps({'frameworkVersion':os.environ.get('MOCK_FLUTTER_VERSION','3.47.8')}))
    elif args[:2] == ['pub', 'get']:
        if os.environ.get('MOCK_FAIL_PUB'):
            sys.exit(2)
    elif args and args[0] == 'run':
        pass
    elif args[:2] in (['build','ios'], ['build','ipa']):
        if os.environ.get('MOCK_SKIP_OUTPUT'):
            sys.exit(0)
        values = {a.split('=',1)[0]: a.split('=',1)[1] for a in args if '=' in a}
        app = root/'build/ios/iphoneos/Runner.app'
        (app/'Frameworks/Flutter.framework').mkdir(parents=True, exist_ok=True)
        (app/'Frameworks/App.framework').mkdir(parents=True, exist_ok=True)
        for item in ['Runner','Frameworks/Flutter.framework/Flutter','Frameworks/App.framework/App']:
            (app/item).write_bytes(b'fake-binary')
        if os.environ.get('MOCK_MISSING_FRAMEWORK'):
            (app/'Frameworks/App.framework/App').unlink()
        info = {'CFBundleIdentifier':'com.nodeman24.belog', 'CFBundleShortVersionString':values['--build-name'],
                'CFBundleVersion':values['--build-number'], 'CFBundleExecutable':'Runner', 'CFBundlePackageType':'APPL',
                'LSRequiresIPhoneOS':True, 'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}
        with (app/'Info.plist').open('wb') as f:
            plistlib.dump(info, f)
        if args[1] == 'ipa':
            out = root/'build/ios/ipa/Runner.ipa'
            out.parent.mkdir(parents=True, exist_ok=True)
            time.sleep(0.02)
            with zipfile.ZipFile(out, 'w') as z:
                for p in app.rglob('*'):
                    if p.is_file(): z.write(p, 'Payload/Runner.app/' + p.relative_to(app).as_posix())
    else:
        sys.exit(1)
else:
    sys.exit(1)
'''


@unittest.skipIf(os.name == 'nt', 'Bash tool mocks run on Unix; Windows exercises PowerShell separately')
class MacScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='belog scripts ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project with spaces'
        self.root.mkdir()
        shutil.copytree(ROOT / 'scripts', self.root / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        (self.root / 'tool/release').mkdir(parents=True)
        shutil.copy2(ROOT / 'tool/release/verify_ipa.py', self.root / 'tool/release/verify_ipa.py')
        shutil.copy2(ROOT / 'pubspec.yaml', self.root / 'pubspec.yaml')
        self.config = self.root / 'env with spaces.json'
        self.config.write_text(json.dumps({'API_BASE_URL': 'https://api.real-site.dev', 'WEB_BASE_URL': ''}))
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        for tool in ('uname', 'xcrun', 'xcodebuild', 'open', 'codesign', 'ditto', 'flutter'):
            path = self.bin / tool
            path.write_text(MOCK_TOOL)
            path.chmod(0o755)
        self.log = Path(self.temp.name) / 'commands.jsonl'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        MOCK_ROOT=str(self.root), MOCK_LOG=str(self.log), TMPDIR=self.temp.name)

    def run_script(self, script, *args, **env):
        return subprocess.run(['bash', str(self.root/'scripts'/script), '--config', str(self.config), *args],
                              env=dict(self.env, **env), text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=20)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_debug_boots_selected_simulator_then_runs_with_config(self):
        result = self.run_script('run_ios.sh')
        self.assertEqual(result.returncode, 0, result.stdout)
        calls = self.calls()
        self.assertIn(['xcrun','simctl','boot','SIM-123'], calls)
        self.assertIn(['xcrun','simctl','bootstatus','SIM-123','-b'], calls)
        run = next(call for call in calls if call[:2] == ['flutter','run'])
        self.assertEqual(run[2:5], ['--debug','-d','SIM-123'])
        self.assertIn('--dart-define-from-file=' + str(self.config), run)
        self.assertIn('--dart-define=BELOG_DEV_BACKEND_CHECK=true', run)

    def test_running_simulator_is_reused_and_boot_timeout_is_reported(self):
        result = self.run_script('run_ios.sh', MOCK_SIM_STATE='Booted')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn(['xcrun','simctl','boot','SIM-123'], self.calls())
        result = self.run_script('run_ios.sh', '--boot-timeout', '1', MOCK_SLOW_BOOT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('timed out', result.stdout)

    def test_altstore_package_is_verified_and_previous_outputs_preserved(self):
        old = self.root/'build/ios/local-ipa/older.ipa'
        old.parent.mkdir(parents=True)
        old.write_bytes(b'keep-me')
        result = self.run_script('build_ios_ipa.sh', '--build-name', '1.2.3', '--build-number', '9')
        self.assertEqual(result.returncode, 0, result.stdout)
        outputs = [p for p in old.parent.glob('*.ipa') if p != old]
        self.assertEqual(len(outputs), 1)
        self.assertEqual(old.read_bytes(), b'keep-me')
        self.assertIn('Ad-hoc only', result.stdout)
        self.assertTrue(zipfile.is_zipfile(outputs[0]))
        self.assertTrue(any(call[0] == 'codesign' and '--sign' in call for call in self.calls()))
        build = next(call for call in self.calls() if call[:3] == ['flutter','build','ios'])
        self.assertIn('--no-codesign', build)
        self.assertIn('--dart-define-from-file=' + str(self.config), build)

    def test_bad_or_failed_altstore_build_cannot_report_success(self):
        for env in ({'MOCK_FAIL_CODESIGN':'1'}, {'MOCK_MISSING_FRAMEWORK':'1'}):
            with self.subTest(env=env):
                result = self.run_script('build_ios_ipa.sh', **env)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn('IPA created:', result.stdout)

    def test_release_refuses_http_and_wrong_flutter(self):
        self.config.write_text(json.dumps({'API_BASE_URL': 'http://localhost:3000'}))
        result = self.run_script('build_ios_ipa.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HTTPS', result.stdout)
        self.assertFalse(any(call[:2] == ['flutter','build'] for call in self.calls()))
        result = self.run_script('run_ios.sh', MOCK_FLUTTER_VERSION='3.0.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('3.47.8', result.stdout)

    def test_signed_mode_checks_new_artifact_and_never_uses_stale_ipa(self):
        options = self.root/'Export Options.plist'
        options.write_text('<plist/>')
        result = self.run_script('build_ios_ipa.sh', '--mode', 'signed', '--export-options', str(options))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('certificate/provisioning still require device verification', result.stdout)
        self.assertTrue(any(call[0] == 'codesign' and '--deep' in call for call in self.calls()))
        result = self.run_script('build_ios_ipa.sh', '--mode', 'signed', '--export-options', str(options), MOCK_SKIP_OUTPUT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale or ambiguous', result.stdout)

    def test_export_rejects_path_traversal_before_extracting(self):
        ipa = self.root/'malicious.ipa'
        with zipfile.ZipFile(ipa, 'w') as z:
            z.writestr('../../escape', 'bad')
        result = subprocess.run(['python3', str(self.root/'scripts/verify_signed_ipa.py'), str(ipa),
                                 'com.nodeman24.belog', '1.0.0', '1'], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unsafe IPA entry', result.stderr)
