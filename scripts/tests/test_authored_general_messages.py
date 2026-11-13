"""Exercise the real general-message CLI against trusted compiled Ruby models."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_stage_authored_patches import gate

ROOT = Path(__file__).resolve().parents[2]
MISC = "ob-issues/1351/misc_communications/001.yaml"
NOTICE = "type: misc_communications\nob_issue_no: '1351'\ncontents: A readable authored notice.\n"


@unittest.skipUnless(os.environ.get("AUTHORED_PATCH_RUBY_TESTS") == "1", "set AUTHORED_PATCH_RUBY_TESTS=1 with service Ruby bundle")
class GeneralMessageModelBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / 'data'
        self.service = self.root / 'service'
        self.data.mkdir()
        self.service.mkdir()
        self.manifest = self.root / 'manifest.json'
        for args in [('init', '-q'), ('config', 'user.name', 'General gate'),
                     ('config', 'user.email', 'gate@example.invalid')]:
            self.git(*args)
        (self.data / 'README.md').write_text('Source baseline\n')
        self.base = self.commit()
        (self.service / 'ituob').symlink_to(ROOT / 'ituob', target_is_directory=True)
        (self.service / 'catalogs').symlink_to(ROOT / 'catalogs', target_is_directory=True)
        metadata = self.service / 'ob-issues/1351/meta.yaml'
        metadata.parent.mkdir(parents=True)
        metadata.write_text('id: 1351\npublication_date: 2026-11-01\ncutoff_date: 2026-10-15\n')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.data), *args], stderr=subprocess.STDOUT).decode().strip()

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '-qm', 'Message fixture')
        return self.git('rev-parse', 'HEAD')

    def run_gate(self, payload, path=MISC):
        target = self.data / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload.encode())
        gate.stage(self.data, self.service, self.base, self.commit(), self.manifest)
        result = subprocess.run(['python3', str(ROOT / 'scripts/stage_authored_patches.py'),
                                 'validate-messages', '--data-root', str(self.data),
                                 '--service-root', str(self.service), '--manifest', str(self.manifest)],
                                text=True, capture_output=True)
        self.assertEqual(payload.encode(), target.read_bytes())
        self.assertEqual(payload.encode(), (self.service / path).read_bytes())
        gate.check(self.data, self.service, self.manifest)
        return result

    def test_plain_misc_notice_uses_hash_or_text_model_without_rewriting(self):
        result = self.run_gate(NOTICE.replace('\n', '\r\n'))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('GeneralMiscCommunications typed model round-trip valid', result.stdout)
        manifest = json.loads(self.manifest.read_text())
        self.assertFalse(manifest['patches'])
        self.assertEqual(MISC, manifest['messages'][0]['path'])

    def test_running_annexes_singleton_model(self):
        result = self.run_gate("type: running_annexes\nob_issue_no: '1351'\nextra_links: [M1400_ICC, BUREAUFAX]\n",
                               'ob-issues/1351/general/running_annexes.yaml')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('GeneralRunningAnnexes typed model round-trip valid', result.stdout)

    def test_approved_recommendations_singleton_with_typed_items(self):
        result = self.run_gate("type: approved_recommendations\nob_issue_no: '1351'\nitems:\n"
                               "- recommendation: X.123\n  approved_date: 2026-11-01\n",
                               'ob-issues/1351/general/approved_recommendations.yaml')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('GeneralApprovedRecommendations typed model round-trip valid', result.stdout)

    def test_existing_corpus_singletons_round_trip_without_normalization(self):
        metadata = self.service / 'ob-issues/1350/meta.yaml'
        metadata.parent.mkdir(parents=True)
        metadata.write_bytes((ROOT / 'ob-issues/1350/meta.yaml').read_bytes())
        for name in ('running_annexes', 'approved_recommendations'):
            path = f'ob-issues/1350/general/{name}.yaml'
            payload = (ROOT / path).read_text()
            result = self.run_gate(payload, path)
            self.assertEqual(0, result.returncode, result.stderr)

    def test_structured_telephone_sections_validate_nested_models(self):
        result = self.run_gate("type: telephone_service_2\nob_issue_no: '1351'\ncontents:\n"
                               "- country_name: {en: Example}\n  phone_code: '999'\n"
                               "  communications:\n  - date: 2026-11-01\n    contents: {en: Authored notice}\n",
                               'ob-issues/1351/telephone_service_2/001.yaml')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('GeneralTelephoneService typed model round-trip valid', result.stdout)

    def test_unknown_dispatch_cannot_be_authorized_by_class_tag(self):
        result = self.run_gate('_class: GeneralMiscCommunications\n' + NOTICE,
                               'ob-issues/1351/unknown_family/001.yaml')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('unrecognized modeled general path', result.stderr)

    def test_unknown_dispatch_without_class_tag_rejected(self):
        result = self.run_gate(NOTICE, 'ob-issues/1351/unknown_family/001.yaml')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('unrecognized modeled general path', result.stderr)

    def test_general_filename_in_register_family_is_not_a_message(self):
        result = self.run_gate(NOTICE, 'ob-issues/1351/dp/001.yaml')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('unrecognized modeled general path', result.stderr)

    def test_path_type_and_class_substitution_rejected(self):
        for payload, message in [(NOTICE.replace('type: misc_communications', 'type: custom'), 'canonical message type mismatch'),
                                 ('_class: GeneralCustom\n' + NOTICE, 'serialized class does not match')]:
            with self.subTest(message=message):
                # Each payload represents an independent append-only data PR.
                self.git('reset', '--hard', self.base)
                self.git('clean', '-fdq')
                staged = self.service / MISC
                if staged.exists():
                    staged.unlink()
                result = self.run_gate(payload)
                self.assertNotEqual(0, result.returncode)
                self.assertIn(message, result.stderr)

    def test_issue_number_must_be_matching_string(self):
        result = self.run_gate(NOTICE.replace("ob_issue_no: '1351'", 'ob_issue_no: 1351'))
        self.assertNotEqual(0, result.returncode)
        self.assertIn('issue id must be the canonical string', result.stderr)

    def test_nested_unknown_structured_item_fields_rejected(self):
        result = self.run_gate("type: approved_recommendations\nob_issue_no: '1351'\nitems:\n"
                               "- recommendation: X.123\n  arbitrary: invalid\n",
                               'ob-issues/1351/general/approved_recommendations.yaml')
        self.assertNotEqual(0, result.returncode)
        self.assertIn('unknown Ituob::Models::GeneralApprovedRecommendation keys', result.stderr)

    def test_invalid_collection_cannot_pass_misc_text_model(self):
        result = self.run_gate(NOTICE.replace('contents: A readable authored notice.', 'contents: [invalid, collection]'))
        self.assertNotEqual(0, result.returncode)


if __name__ == '__main__':
    unittest.main()
