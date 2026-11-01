"""Small static guardrails; CI still executes the real PR build paths."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MobileWorkflowContractTests(unittest.TestCase):
    def test_manual_builds_are_separate_from_untrusted_pr_validation(self):
        workflow = (ROOT / '.github/workflows/mobile-packages.yml').read_text()
        self.assertIn('workflow_dispatch:', workflow)
        self.assertIn('pull_request:', workflow)
        self.assertNotIn('pull_request_target:', workflow)
        self.assertIn('contents: read', workflow)
        self.assertNotIn('continue-on-error: true', workflow)
        ios = workflow.split('\n  ios:\n', 1)[1].split('\n  android-fixture:\n', 1)[0]
        self.assertNotIn('secrets.', ios)
        self.assertNotIn('environment: production', ios)
        self.assertIn("github.event_name == 'workflow_dispatch' && success()", ios)
        fixture = workflow.split('\n  android-fixture:\n', 1)[1].split('\n  android-fixture-debug:\n', 1)[0]
        debug_fixture = workflow.split('\n  android-fixture-debug:\n', 1)[1].split('\n  android-personal:\n', 1)[0]
        for job in (fixture, debug_fixture):
            self.assertIn("github.event_name == 'pull_request'", job)
            self.assertNotIn('secrets.', job)
            self.assertNotIn('environment: production', job)
            self.assertIn('needs: prepare', job)
            self.assertIn('build_android_package.sh', job)
            self.assertIn('statuses=("${PIPESTATUS[@]}")', job)
            self.assertIn('df -h "$GITHUB_WORKSPACE" "$RUNNER_TEMP"', job)
        self.assertIn(' personal "$ANDROID_RELEASE_CERT_SHA256"', fixture)
        self.assertNotIn(' debug - ', fixture)
        self.assertIn(' debug - ', debug_fixture)
        self.assertNotIn(' personal ', debug_fixture)
        self.assertNotIn('ANDROID_KEYSTORE_PASSWORD', debug_fixture)
        personal = workflow.split('\n  android-personal:\n', 1)[1].split('\n  android-debug:\n', 1)[0]
        self.assertIn("github.event_name == 'workflow_dispatch'", personal)
        self.assertIn('environment: production', personal)
        self.assertIn('build_android_package.sh', personal)
        self.assertIn('prepare_android_signing.py', personal)
        self.assertIn('needs.prepare.outputs.api_origin', personal)

    def test_tag_release_uses_the_checked_shared_package_paths(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn('tool/mobile/build_ios_package.sh', workflow)
        self.assertIn('tool/mobile/verify_android_package.sh', workflow)
        self.assertNotIn('-exec codesign', workflow)


if __name__ == '__main__':
    unittest.main()
