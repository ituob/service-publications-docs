"""Public regressions for the exact-commit authored patch boundary (stdlib only)."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("gate", Path(__file__).parents[1] / "stage_authored_patches.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
PATCH = "ob-issues/1351/e212-mnc/001-ADD.yaml"
META = "ob-issues/1351/meta.yaml"
PAYLOAD = b"# exact comment\r\ntype: ADD\r\ndata: {networks: 'arbitrary spacing'}\r\n"


class StageAuthoredPatchesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / "data"
        self.service = self.root / "service"
        self.data.mkdir()
        self.service.mkdir()
        self.manifest = self.root / "manifest.json"
        self.git("init", "-q")
        self.git("config", "user.name", "Gate test")
        self.git("config", "user.email", "gate@example.invalid")
        self.write(self.data, "issues/1350/source.yaml", b"original source\n")
        self.base = self.commit()
        self.write(self.service, META, b"id: 1351\n")
        self.write(self.service, "ob-issues/1350/meta.yaml", b"id: 1350\n")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.data), *args], stderr=subprocess.STDOUT).decode().strip()

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "Fixture change")
        return self.git("rev-parse", "HEAD")

    def write(self, root, name, payload):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    def stage(self, head=None):
        return gate.stage(self.data, self.service, self.base, head or self.commit(), self.manifest)

    def test_exact_head_bytes_preserved_and_unrelated_source_untouched(self):
        self.write(self.data, PATCH, PAYLOAD)
        source = (self.data / "issues/1350/source.yaml").read_bytes()
        historical = (self.service / "ob-issues/1350/meta.yaml").read_bytes()
        head = self.commit()
        manifest = self.stage(head)
        self.assertEqual(PAYLOAD, (self.service / PATCH).read_bytes())
        self.assertEqual(PAYLOAD, gate.git(self.data, "show", f"{head}:{PATCH}"))
        self.assertEqual(source, (self.data / "issues/1350/source.yaml").read_bytes())
        self.assertEqual(historical, (self.service / "ob-issues/1350/meta.yaml").read_bytes())
        self.assertEqual(gate.digest(PAYLOAD), manifest["patches"][0]["sha256"])
        self.assertEqual(manifest, gate.check(self.data, self.service, self.manifest))

    def test_data_checkout_must_be_exact_head(self):
        self.write(self.data, PATCH, PAYLOAD)
        self.commit()
        with self.assertRaisesRegex(ValueError, "HEAD does not match"):
            self.stage(self.base)

    def test_dirty_patch_cannot_replace_head_blob(self):
        self.write(self.data, PATCH, PAYLOAD)
        head = self.commit()
        self.write(self.data, PATCH, b"dirty")
        with self.assertRaisesRegex(ValueError, "differs from head blob"):
            self.stage(head)

    def test_references_must_be_full_commits(self):
        with self.assertRaisesRegex(ValueError, "explicit lowercase"):
            gate.stage(self.data, self.service, "main", self.base, self.manifest)

    def test_exact_diff_recorded_and_prior_authored_head_preserved(self):
        self.write(self.data, "ob-issues/1351/e212-mnc/000-ADD.yaml", b"already on base")
        self.base = self.commit()
        self.write(self.data, PATCH, PAYLOAD)
        manifest = self.stage()
        self.assertEqual([PATCH], manifest["changed_paths"])
        self.assertEqual(b"already on base", (self.service / "ob-issues/1351/e212-mnc/000-ADD.yaml").read_bytes())
        self.assertEqual(2, len(manifest["patches"]))

    def test_historical_collision_fails_without_overwrite(self):
        self.write(self.service, PATCH, b"historical bytes")
        self.write(self.data, PATCH, PAYLOAD)
        with self.assertRaisesRegex(ValueError, f"collision.*{PATCH}"):
            self.stage()
        self.assertEqual(b"historical bytes", (self.service / PATCH).read_bytes())
        self.assertFalse(self.manifest.exists())

    def test_identical_historical_copy_supported(self):
        self.write(self.service, PATCH, PAYLOAD)
        self.write(self.data, PATCH, PAYLOAD)
        self.assertEqual(1, len(self.stage()["patches"]))

    def test_modified_and_deleted_authored_history_rejected(self):
        self.write(self.data, PATCH, PAYLOAD)
        self.base = self.commit()
        self.write(self.data, PATCH, b"rewrite")
        head = self.commit()
        with self.assertRaisesRegex(ValueError, "history cannot be modified/deleted"):
            self.stage(head)
        (self.data / PATCH).unlink()
        head = self.commit()
        with self.assertRaisesRegex(ValueError, "history cannot be modified/deleted"):
            self.stage(head)

    def test_new_issue_requires_metadata(self):
        (self.service / META).unlink()
        self.write(self.data, PATCH, PAYLOAD)
        with self.assertRaisesRegex(ValueError, "metadata prerequisite missing"):
            self.stage()
        self.assertFalse((self.service / PATCH).exists())

    def test_new_issue_can_add_metadata_with_actions_and_hashes_both(self):
        (self.service / META).unlink()
        self.write(self.data, PATCH, PAYLOAD)
        self.write(self.data, META, b"id: 1351\npublication_date: 2026-11-15\n")
        manifest = self.stage()
        self.assertEqual({META, PATCH}, {item["path"] for item in manifest["patches"]})
        self.assertEqual((self.data / META).read_bytes(), (self.service / META).read_bytes())
        gate.check(self.data, self.service, self.manifest)

    def test_patch_symlink_rejected(self):
        path = self.data / PATCH
        path.parent.mkdir(parents=True)
        path.symlink_to("../../../issues/1350/source.yaml")
        with self.assertRaisesRegex(ValueError, "symlink/submodule"):
            self.stage()

    def test_stage_parent_symlink_rejected(self):
        self.write(self.data, PATCH, PAYLOAD)
        destination = self.service / "ob-issues/1351/e212-mnc"
        destination.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink path"):
            self.stage()
        self.assertFalse((self.root / "001-ADD.yaml").exists())

    def test_executable_patch_rejected(self):
        self.write(self.data, PATCH, PAYLOAD).chmod(0o755)
        with self.assertRaisesRegex(ValueError, "nonexecutable regular"):
            self.stage()

    def test_unknown_and_generated_paths_rejected(self):
        for path in ("unrecognized.yaml", "datasets/current/data.yaml", "snapshots/e212-mnc/current.json",
                     "ob-issues/1351/e212-mnc/full-state.yaml", "ob-issues/1351/e212-mnc/001-UNKNOWN.yaml"):
            with self.subTest(path=path):
                self.git("reset", "--hard", self.base)
                self.git("clean", "-fdq")
                self.write(self.data, path, b"bad")
                with self.assertRaisesRegex(ValueError, "unsupported or generated-state"):
                    self.stage()

    def test_traversal_rejected(self):
        for path in ("../outside", "/outside", "ob-issues/../outside", "./outside"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "unsafe path"):
                gate.safe_path(self.service, path)

    def test_source_change_allowed_and_parser_baseline_marked_inapplicable(self):
        self.write(self.data, "issues/1351/amendments.yaml", b"messages: []\n")
        self.assertTrue(self.stage()["source_changed"])

    def test_inert_caller_scripts_allowed_without_execution_or_source_rewrite(self):
        script = b"#!/bin/sh\nexit 97 # must never be executed by service gate\n"
        names = (".github/scripts/check-patch-log.sh", ".github/scripts/check-patch-log-selftest.sh",
                 ".github/scripts/check_patch_log.py")
        for name in names:
            self.write(self.data, name, script).chmod(0o755)
        self.write(self.data, PATCH, PAYLOAD)
        manifest = self.stage()
        self.assertFalse(manifest["source_changed"])
        self.assertEqual([PATCH], manifest["changed_paths"])
        self.assertEqual(PAYLOAD, (self.service / PATCH).read_bytes())
        for name in names:
            self.assertEqual(script, (self.data / name).read_bytes())
            self.assertFalse((self.service / name).exists())

    def test_caller_script_allowlist_does_not_allow_nested_or_generated_paths(self):
        forbidden = (".github/scripts/nested/check.py", ".github/scripts/current.json",
                     ".github/scripts/schema.yaml", ".github/scripts/.hidden.sh",
                     "scripts/check-patch-log.sh", "lists/list.yaml", "reference-docs/seed.yaml")
        for path in forbidden:
            with self.subTest(path=path):
                self.git("reset", "--hard", self.base)
                self.git("clean", "-fdq")
                self.write(self.data, path, b"unclassified")
                with self.assertRaisesRegex(ValueError, "unsupported or generated-state"):
                    self.stage()

    def test_manifest_cannot_hide_changed_bytes(self):
        self.write(self.data, PATCH, PAYLOAD)
        self.stage()
        for root in (self.data, self.service):
            with self.subTest(root=str(root)):
                self.write(root, PATCH, b"normalized or tampered")
                with self.assertRaisesRegex(ValueError, "bytes changed"):
                    gate.check(self.data, self.service, self.manifest)
                self.write(root, PATCH, PAYLOAD)
        manifest = json.loads(self.manifest.read_text())
        manifest["patches"][0]["sha256"] = "0" * 64
        self.manifest.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "manifest differs from exact head blob"):
            gate.check(self.data, self.service, self.manifest)


if __name__ == "__main__":
    unittest.main()
