"""Regression and adversarial fixtures for the offline documentation gate."""
from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from doc_contract.evidence import ManifestError, parse_manifest
from doc_contract.markdown import SourceLine, heading_anchors, inline_codes, links, visible_lines
from doc_contract.model import Diagnostic, Repository
from doc_contract.reporting import github_annotation
from doc_contract.rules import check
from doc_contract.paths import PatternError, path_exists


class ReportingTest(unittest.TestCase):
    def test_annotation_escapes_commands_and_caps_input(self):
        annotation = github_annotation(Diagnostic('docs/a,b.md', 4, 'path', 'bad%\n::warning::x'))
        self.assertIn('file=docs/a%2Cb.md,line=4', annotation)
        self.assertIn('bad%25%0A::warning::x', annotation)
        self.assertNotIn('\n', annotation)
        self.assertLess(len(github_annotation(Diagnostic('x', 1, 'test', '%\n' * 5000))), 3500)

class MarkdownScannerTest(unittest.TestCase):
    def test_fences_and_comments_preserve_real_line_numbers(self):
        text = '''# Title
<!-- start
[hidden](fake.md)
-->visible
```dart
`lib/hidden.dart`
```
~~~
[hidden](fake.md)
~~~~
[shown](page.md)
'''
        lines = list(visible_lines(text))
        self.assertEqual([(link.line, link.destination) for link in links(lines)], [(11, 'page.md')])
        self.assertEqual(next(line.text for line in lines if line.number == 4), ' visible')
        self.assertFalse(any(line.number in (6, 9) for line in lines))

    def test_short_fence_does_not_close_long_fence(self):
        text = '````\n```\n`lib/no.dart`\n````\n`lib/yes.dart`\n'
        found = [code.value for line in visible_lines(text) for code in inline_codes(line)]
        self.assertEqual(found, ['lib/yes.dart'])

    def test_inline_delimiters_escaped_ticks_and_unclosed_code(self):
        line = SourceLine(12, r'\`fake\` ``lib/real.dart`` `lib/other.dart` `unfinished')
        self.assertEqual([(c.line, c.value) for c in inline_codes(line)],
                         [(12, 'lib/real.dart'), (12, 'lib/other.dart')])

    def test_links_reference_nested_destination_images_and_code(self):
        text = '''[One](file_(1).md "title") ![image](image.png)
[Two][ref] [ref][] `[hidden](bad.md)`
[ref]: <folder/file.md> "title"
'''
        found = list(links(list(visible_lines(text))))
        self.assertEqual([(item.destination, item.image) for item in found],
                         [('file_(1).md', False), ('image.png', True),
                          ('folder/file.md', False), ('folder/file.md', False)])

    def test_heading_duplicates_unicode_and_code(self):
        lines = list(visible_lines('# Hello World\n# Hello World\n# 中文 `code`\n'))
        self.assertEqual(heading_anchors(lines), {'hello-world', 'hello-world-1', '中文-code'})


class PathMatcherTest(unittest.TestCase):
    def test_recursive_glob_does_not_follow_symlink_or_escape_root(self):
        with TemporaryDirectory() as temporary, TemporaryDirectory() as outside:
            root = Path(temporary)
            (root / 'lib').mkdir()
            (root / 'lib' / 'sub').mkdir()
            (root / 'lib' / 'sub' / 'inside.dart').write_text('ok')
            (Path(outside) / 'private.dart').write_text('no')
            (root / 'lib' / 'cycle').symlink_to(root / 'lib', target_is_directory=True)
            (root / 'lib' / 'external').symlink_to(outside, target_is_directory=True)
            self.assertTrue(path_exists(root, 'lib/**/*.dart'))
            self.assertFalse(path_exists(root, 'lib/**/private.dart'))
            with self.assertRaises(PatternError):
                path_exists(root, 'lib/\x00bad')
            with self.assertRaises(PatternError):
                path_exists(root, 'lib/../../private.dart')
            with self.assertRaises(PatternError):
                path_exists(root, 'lib/external/private.dart')

    def test_scan_budget_fails_closed(self):
        from unittest.mock import patch
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'lib').mkdir()
            for name in ('a', 'b', 'c'):
                (root / 'lib' / name).write_text('x')
            # Constructing a custom budget avoids changing the public default.
            from doc_contract import paths
            with patch.object(paths, '_Budget', return_value=paths._Budget(1)):
                with self.assertRaises(PatternError):
                    path_exists(root, 'lib/*.dart')


class DocContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.write('README.md', '# Root\n')
        self.write('docs/README.md', '# Index\n\n- [Page](page.md)\n')
        self.write('docs/page.md', '# Page\n\n> 状态：active | 分类基线：`a123456`\n\n# Section\n')
        self.write('lib/example.dart', 'example value\n')
        self.manifest = {'version': 1, 'claims': [{
            'id': 'example-claim', 'description': 'check example',
            'documents': [{'path': 'README.md', 'contains': ['# Root'], 'absent': []}],
            'sources': [{'path': 'lib/example.dart', 'contains': ['example'], 'absent': ['removed']}],
        }]}
        self.save_manifest()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def save_manifest(self):
        self.write('tool/ci/doc-claim-evidence.json', json.dumps(self.manifest))

    def diagnostics(self):
        repository = Repository(self.root)
        repository.load()
        return check(repository)

    def assert_rule(self, rule):
        errors = self.diagnostics()
        self.assertIn(rule, [error.rule for error in errors], [error.render() for error in errors])

    def test_valid_repository_and_relative_local_anchor(self):
        self.write('README.md', '# Root\n[section](docs/page.md#section)\n')
        self.assertEqual(self.diagnostics(), [])

    def test_index_missing_duplicate_and_nonexistent(self):
        self.write('docs/README.md', '[page](page.md)\n[again](page.md)\n[missing](gone.md)\n')
        self.assert_rule('index-duplicate')
        self.assert_rule('index-link')
        self.write('docs/README.md', '# Index\n![Page](page.md)\n')
        self.assert_rule('index-missing')
        self.write('docs/README.md', '[](page.md)\n')
        self.assert_rule('index-link')

    def test_archived_and_draft_status_visible_in_index(self):
        self.write('docs/page.md', '# Page\n> 状态：archived | 分类基线：`a123456`\n')
        self.assert_rule('index-status')
        self.write('docs/README.md', '[Page](page.md)（draft）\n')
        self.assert_rule('index-status')
        self.write('docs/README.md', '[Page](page.md)（archived）\n')
        self.assertEqual(self.diagnostics(), [])

    def test_reference_style_index_link_and_percent_encoded_destination(self):
        self.write('docs/README.md', '[Page][p]\n\n[p]: page%2Emd\n')
        self.assertEqual(self.diagnostics(), [])

    def test_missing_or_duplicate_status_and_status_in_code(self):
        self.write('docs/page.md', '# P\n```\n> 状态：active | 分类基线：`a123456`\n```\n')
        self.assert_rule('status')
        self.write('docs/page.md', '# P\n> 状态：draft | 分类基线：`a123456`\n> 状态：active | 分类基线：`a123456`\n')
        self.assert_rule('status')
        self.write('docs/page.md', '# P\n> 状态：active | 分类基线：`a123456`\n> 状态：pending | 分类基线：`bad`\n')
        self.assert_rule('status')

    def test_live_issue_claim_fails_but_dated_archive_is_allowed(self):
        self.write('README.md', '# Root\n当前只剩 **#18**（举报）开放。\n')
        self.assert_rule('live-issues')
        self.write('README.md', '# Root\n')
        self.write('docs/README.md', '[Page](page.md)（archived）\n')
        self.write('docs/page.md', '# Page\n> 状态：archived | 分类基线：`a123456`\n\n2026-11-05 只剩 #18 开放。\n')
        self.assertEqual(self.diagnostics(), [])
        self.write('docs/page.md', '# Page\n> 状态：archived | 分类基线：`a123456`\n\n2026-02-31 只剩 #18 开放。\n')
        self.assert_rule('live-issues')

    def test_current_claim_in_fence_is_not_prose(self):
        self.write('README.md', '# Root\n```\n只剩 #18 开放\n```\n')
        self.assertEqual(self.diagnostics(), [])

    def test_paths_missing_globs_and_outside_root(self):
        self.write('README.md', '# Root\n`lib/example.dart` `lib/**/*.dart` `lib/missing.dart`\n')
        errors = self.diagnostics()
        self.assertEqual([error.rule for error in errors], ['path'])
        self.assertIn('lib/missing.dart', errors[0].message)
        self.write('README.md', '# Root\n`lib/../../outside`\n')
        self.assert_rule('path')

    def test_invalid_local_link_and_anchor(self):
        self.write('README.md', '# Root\n[broken](docs/page.md#unknown)\n')
        self.assert_rule('anchor')
        self.write('README.md', '# Root\n[broken](docs/missing.md)\n')
        self.assert_rule('link')
        self.write('README.md', '# Root\n[outside](../outside)\n')
        self.assert_rule('link')

    def test_external_links_do_not_access_network(self):
        self.write('README.md', '# Root\n[remote](https://invalid.example/missing)\n')
        self.assertEqual(self.diagnostics(), [])

    def test_large_document_and_cyclic_link_fail_closed(self):
        from doc_contract.model import MAX_DOCUMENT_BYTES
        self.write('docs/page.md', 'x' * (MAX_DOCUMENT_BYTES + 1))
        self.assert_rule('read')
        self.write('docs/page.md', '# Page\n> 状态：active | 分类基线：`a123456`\n')
        cycle = self.root / 'lib' / 'cycle'
        cycle.symlink_to(cycle)
        self.write('README.md', '# Root\n[cycle](lib/cycle)\n')
        self.assert_rule('link')

    def test_evidence_detects_code_and_prose_drift(self):
        self.write('lib/example.dart', 'changed')
        self.assert_rule('evidence')
        self.write('lib/example.dart', 'example\nremoved')
        errors = self.diagnostics()
        self.assertEqual(errors[0].line, 2)
        self.assertIn("'removed'", errors[0].message)
        self.assert_rule('evidence')
        self.write('README.md', '# Other\n')
        self.assert_rule('evidence')

    def test_evidence_manifest_fail_closed(self):
        self.manifest['claims'][0]['sources'][0]['path'] = 'lib/../../secret'
        self.save_manifest()
        self.assert_rule('evidence-manifest')
        self.write('tool/ci/doc-claim-evidence.json', '{"version":1,"version":1,"claims":[]}')
        self.assert_rule('evidence-manifest')
        self.write('tool/ci/doc-claim-evidence.json', '{')
        self.assert_rule('evidence-manifest')

    def test_manifest_rejects_empty_or_conflicting_markers(self):
        entry = self.manifest['claims'][0]['sources'][0]
        entry['contains'] = []
        entry['absent'] = []
        with self.assertRaises(ManifestError):
            parse_manifest(json.dumps(self.manifest))
        entry['contains'] = ['x']
        entry['absent'] = ['x']
        with self.assertRaises(ManifestError):
            parse_manifest(json.dumps(self.manifest))

    def test_cli_exit_and_diagnostics(self):
        script = Path(__file__).with_name('check_doc_claims.py')
        good = subprocess.run([sys.executable, str(script), '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.write('README.md', '# Root\n`lib/absent.dart`\n')
        bad = subprocess.run([sys.executable, str(script), '--root', str(self.root)], capture_output=True, text=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn('README.md:2: [path]', bad.stderr)
        output = subprocess.run([sys.executable, str(script), '--root', str(self.root), '--format', 'json'], capture_output=True, text=True)
        result = json.loads(output.stdout)
        self.assertEqual(output.returncode, 1)
        self.assertFalse(result['ok'])
        self.assertEqual(result['diagnostics'][0]['rule'], 'path')
        annotated = subprocess.run([sys.executable, str(script), '--root', str(self.root), '--format', 'github'], capture_output=True, text=True)
        self.assertEqual(annotated.returncode, 1)
        self.assertIn('::error file=README.md,line=2', annotated.stdout)

    def test_real_repository_obeys_contract(self):
        repository = Repository(Path(__file__).resolve().parents[2])
        repository.load()
        self.assertEqual([error.render() for error in check(repository)], [])


if __name__ == '__main__':
    unittest.main()
