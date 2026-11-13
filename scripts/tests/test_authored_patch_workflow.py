"""Run the real workflow Ruby model boundaries when the service bundle is available.

AUTHORED_PATCH_RUBY_TESTS=1 BUNDLE_GEMFILE=ituob/Gemfile python3 -m unittest discover -s scripts/tests
"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/validate-itu-ob-data.yml"
BLOCKS = [textwrap.dedent(block) for block in re.findall(r"<<'RUBY'\n(.*?)\n          RUBY", WORKFLOW.read_text(), re.S)]
PATCH = "ob-issues/1351/e212-mnc/001-ADD.yaml"
VALID = """type: ADD
ob_issue_no: '1351'
identifier: {code: '1351-001'}
data:
  _class: E212MNCAmendment
  entries:
  - mcc_mnc_codes: '999 99'
    country_or_area: {en: Example}
    networks: Exact authored input
"""


@unittest.skipUnless(os.environ.get("AUTHORED_PATCH_RUBY_TESTS") == "1", "set AUTHORED_PATCH_RUBY_TESTS=1 with service Ruby bundle")
class WorkflowModelBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = dict(os.environ, BUNDLE_GEMFILE=str(ROOT / 'ituob/Gemfile'),
                        AUTHORED_MANIFEST=str(self.root / 'manifest.json'),
                        SNAPSHOTS_OUT=str(self.root / 'snapshots'))

    def run_gate(self, payload, path=PATCH, block=0):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(payload)
        (self.root / 'manifest.json').write_text(json.dumps({'patches': [{'path': path}]}))
        return subprocess.run(['bundle', 'exec', 'ruby', '-I' + str(ROOT / 'ituob/lib'),
                               '-rituob', '-rjson', '-ryaml', '-rdate'], input=BLOCKS[block],
                              text=True, capture_output=True, cwd=self.root, env=self.env)

    def assert_rejected(self, payload, message, **kwargs):
        result = self.run_gate(payload, **kwargs)
        self.assertNotEqual(0, result.returncode, result.stdout)
        self.assertIn(message, result.stderr)

    def test_valid_authored_envelope_and_nested_items(self):
        result = self.run_gate(VALID)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_top_level_class_cannot_bypass_envelope(self):
        self.assert_rejected('_class: IssueMetadata\n' + VALID, 'serialized class does not match Ituob::Registers::Change')

    def test_filename_action_must_match_declared_action(self):
        self.assert_rejected(VALID.replace('type: ADD', 'type: MOD'), 'type/filename mismatch')

    def test_issue_directory_must_match_envelope(self):
        self.assert_rejected(VALID.replace("ob_issue_no: '1351'", "ob_issue_no: '1350'"), 'issue id mismatch')

    def test_arbitrary_payload_class_rejected(self):
        self.assert_rejected(VALID.replace('E212MNCAmendment', 'IssueMetadata'), 'amendment class mismatch')

    def test_nested_unknown_item_key_rejected(self):
        self.assert_rejected(VALID + '    invented_full_state: true\n', 'unknown Ituob::Models::E212MNCEntry keys')

    def test_nested_polymorphic_substitution_rejected(self):
        self.assert_rejected(VALID + '    _class: IssueMetadata\n', 'serialized class does not match')

    def test_issue_metadata_passes_with_matching_id_and_dates(self):
        result = self.run_gate('id: 1351\npublication_date: 2026-11-01T00:00:00Z\ncutoff_date: 2026-10-15\n',
                               path='ob-issues/1351/meta.yaml')
        self.assertEqual(0, result.returncode, result.stderr)

    def test_metadata_wrong_id_and_invalid_date_rejected(self):
        self.assert_rejected('id: 1350\n', 'issue id mismatch', path='ob-issues/1351/meta.yaml')
        self.assert_rejected('id: 1351\npublication_date: [invalid]\ncutoff_date: 2026-10-15\n',
                             'invalid publication_date', path='ob-issues/1351/meta.yaml')

    def test_metadata_union_model_cannot_hide_unknown_fields(self):
        self.assert_rejected('id: 1351\npublication_date: 2026-11-01\ncutoff_date: 2026-10-15\n'
                             'authors: [{name: {en: Example, arbitrary: invalid}}]\n',
                             'unknown Ituob::Models::MultilingualString keys', path='ob-issues/1351/meta.yaml')

    def test_add_history_without_active_entry_cannot_pass_snapshot_proof(self):
        change = self.root / 'datasets/1162-E.212/changes/1351-0001-ADD-proof.yaml'
        change.parent.mkdir(parents=True)
        change.write_text("identifier: {code: '999 99'}\n")
        snapshot = self.root / 'snapshots/e212-mnc/at-1351.json'
        snapshot.parent.mkdir(parents=True)
        snapshot.write_text(json.dumps({'history': [{'ob_issue': 1351, 'type': 'ADD',
                                                    'identifier': {'code': '999 99'}}],
                                       'errors': [], 'active_entries': []}))
        self.assert_rejected(VALID, "incoming ADD key \"999 99\" absent from snapshot", block=1)

    def test_authored_patch_ignored_by_migration_cannot_pass_replay_gate(self):
        self.assert_rejected(VALID, 'authored patch ignored by migration/replay', block=1)


if __name__ == '__main__':
    unittest.main()
