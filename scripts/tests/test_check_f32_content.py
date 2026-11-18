"""Focused checks for the content gate, independent of PDF layout/page drift."""

import importlib.util
import json
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check_f32_content.py"
SPEC = importlib.util.spec_from_file_location("check_f32_content", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class F32ContentTests(unittest.TestCase):
    def setUp(self):
        self.expected = json.loads(gate.FIXTURE.read_text())
        self.text = ("\n".join(self.expected["countries"])
                     + "\nGK- - LU- - MG- -\n"
                     + "\n".join(note["en"] for note in self.expected["notes"]))

    def test_complete_content_survives_wrapping_and_punctuation(self):
        self.assertEqual([], gate.content_errors(self.text.replace(" ", "\n"), "en", self.expected))

    def test_missing_tail_of_note_fails_even_with_the_same_page_count(self):
        note = self.expected["notes"][-1]["en"]
        damaged = self.text.replace(note, note[:95]) + "\f" * 47
        self.assertTrue(any("missing complete note" in error
                            for error in gate.content_errors(damaged, "en", self.expected)))

    def test_adjacent_roa_column_does_not_interrupt_wrapped_country(self):
        wrapped = self.text.replace("SAINT HELENA, ASCENSION AND TRISTAN DA CUNHA",
                                    "SAINT HELENA, ASCENSION     Briars\nAND TRISTAN DA CUNHA    AV- -")
        self.assertEqual([], gate.content_errors(wrapped, "en", self.expected))

    def test_reservation_after_zimbabwe_fails(self):
        damaged = self.text.replace("ANTIGUA AND BARBUDA\n", "") + "\nANTIGUA AND BARBUDA"
        self.assertIn("country out of printed order: AUSTRIA",
                      gate.content_errors(damaged, "en", self.expected))

    def test_code_in_prose_cannot_replace_network_cell(self):
        damaged = self.text.replace("GK- -", "")
        self.assertIn("missing network code cell: GK- -",
                      gate.content_errors(damaged, "en", self.expected))

    def test_appendix_cannot_mask_missing_destination_note(self):
        note = self.expected["notes"][-1]["en"]
        damaged = self.text.replace(note, "") + "\nAppendix 1: Codes\n" + note
        self.assertTrue(any("missing complete note" in error
                            for error in gate.content_errors(damaged, "en", self.expected)))


if __name__ == "__main__":
    unittest.main()
