"""Public regressions for ordered print comparison, independent of replay data."""

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check_f32_content.py"
SPEC = importlib.util.spec_from_file_location("check_f32_content", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def row(country="", network="", code="", office="", office_code=""):
    return f"{country:<32}  {network:<38}  {code:<12}  {office:<30}  {office_code}"


HEADER = row("Country / geographical area", "Network (administration/ROA)",
             "Network code", "Name of Telegraph Office", "Office code")
COUNTRIES = [[name] * 3 for name in ("GIBRALTAR", "LUXEMBOURG", "VANUATU", "ZIMBABWE")]


def country(name, code, note=""):
    result = [row(name, "Printed operator", code), row(name), row(name),
              row("", "", "", "All destinations", code[:2] + "XX")]
    if note:
        result.append("1) " + note)
    return "\n".join(result)


NOTE = "The telegram service is no longer accepted. The two-letter code remains reserved."
PRINTED = HEADER + "\n" + "\n".join([
    country("GIBRALTAR", "GK- -"), country("LUXEMBOURG", "LU- -"),
    country("VANUATU", "VU- -", NOTE), country("ZIMBABWE", "ZW- -")])


class F32ContentTests(unittest.TestCase):
    def errors(self, text, source=PRINTED, countries=COUNTRIES):
        return gate.comparison_errors(source, text, "en", {}, countries)

    def test_printed_baseline_and_page_drift_are_preserved(self):
        self.assertEqual([], self.errors(PRINTED))
        self.assertEqual([], self.errors(PRINTED + "\f" * 47))

    def test_canonical_reflow_preserves_punctuation_and_qualifiers(self):
        self.assertEqual(gate.canonical("Telecommuni-\ncations ‘office’."),
                         gate.canonical("Telecommunications 'office'."))
        self.assertNotEqual(gate.canonical("Office (i)"), gate.canonical("Office (ii)"))
        self.assertNotEqual(gate.canonical("Code: XX"), gate.canonical("Code XX"))

    def test_swap_codes_fails_in_the_country_that_owns_each_code(self):
        damaged = PRINTED.replace("GK- -", "TEMP").replace("LU- -", "GK- -").replace("TEMP", "LU- -")
        errors = self.errors(damaged)
        self.assertTrue(any("GIBRALTAR: network code" in error for error in errors), errors)
        self.assertTrue(any("LUXEMBOURG: network code" in error for error in errors), errors)

    def test_move_note_to_end_fails_even_though_note_is_complete(self):
        damaged = PRINTED.replace("1) " + NOTE, "") + "\n1) " + NOTE
        errors = self.errors(damaged)
        self.assertTrue(any("VANUATU" in error and "notes" in error for error in errors), errors)
        self.assertTrue(any("ZIMBABWE" in error and "notes" in error for error in errors), errors)

    def test_note_cannot_move_past_another_row_within_country(self):
        extra = "\n" + row("", "Second network", "ZX- -", "Second office", "ZXXX")
        source = PRINTED + "\n1) Local routing qualification." + extra
        damaged = PRINTED + extra + "\n1) Local routing qualification."
        errors = self.errors(damaged, source)
        self.assertTrue(any("ZIMBABWE" in error and "placement" in error for error in errors), errors)

    def test_network_code_displacement_cannot_preserve_row_association(self):
        source = PRINTED + "\n" + row("", "Second network", "ZX- -", "Second office", "ZXXX")
        damaged = source.replace(row("ZIMBABWE", "Printed operator", "ZW- -"),
                                 row("ZIMBABWE", "Printed operator"))
        damaged = damaged.replace(row("", "", "", "All destinations", "ZWXX"),
                                  row("", "", "", "All destinations", "ZWXX") + "\n" + row("", "", "ZW- -"))
        errors = self.errors(damaged, source)
        self.assertTrue(any("ZIMBABWE: row association" in error for error in errors), errors)

    def test_old_global_gate_blind_spot_missing_qualifier_is_red(self):
        # Countries, complete cessation notes and GK/LU codes all remain present;
        # the old substring gate accepted a lost routing qualifier on this input.
        source = PRINTED.replace("Printed operator", "Printed operator (routing only)", 1)
        errors = self.errors(PRINTED, source)
        self.assertTrue(any("GIBRALTAR: network/ROA" in error for error in errors), errors)

    def test_appendix_cannot_mask_missing_destination_note(self):
        damaged = PRINTED.replace("1) " + NOTE, "") + "\nAppendix 1: Codes\n1) " + NOTE
        self.assertTrue(any("VANUATU" in error for error in self.errors(damaged)))

    def test_official_pdfs_are_fully_scoped_and_self_preserving(self):
        for language in gate.LANGUAGES.values():
            with self.subTest(language=language):
                text = gate.official_text(language)
                countries = gate.official_countries(language)
                sections, errors = gate.country_sections(text, countries)
                self.assertEqual([], errors)
                self.assertEqual(233, len(sections))
                self.assertEqual([], gate.comparison_errors(text, text, language, {}, countries))


if __name__ == "__main__":
    unittest.main()
