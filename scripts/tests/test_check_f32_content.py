"""Public regressions for ordered print comparison, independent of replay data."""

import importlib.util
from pathlib import Path
import re
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


def bbox(text, squeeze=()):
    """pdftotext -bbox output for column-aligned text: word x comes from the
    character offset, so cells stay in their printed columns. A cell whose text
    is in `squeeze` ends 11.5 pt before the next cell (the measured SAINT
    PIERRE ET MIQUELON gap), which -layout would print as a single space."""
    pages = []
    for page in text.split("\f"):
        words = []
        for number, line in enumerate(page.splitlines()):
            chunks = list(re.finditer(r"\S(?:.*?\S)?(?= {2,}|$)", line))
            for index, chunk in enumerate(chunks):
                x = 34.0 + chunk.start() * 3.0
                nxt = 34.0 + chunks[index + 1].start() * 3.0 if index + 1 < len(chunks) else None
                for word in chunk.group().split(" "):
                    width = 3.0 * len(word)
                    if chunk.group() in squeeze and word == chunk.group().split(" ")[-1] and nxt:
                        width = nxt - 11.5 - x  # stretched: ends 11.5 pt before the next cell
                    words.append(f'<word xMin="{x:.3f}" yMin="{10 * number + 100:.3f}" '
                                 f'xMax="{x + width:.3f}" yMax="{10 * number + 110:.3f}">{word}</word>')
                    x += width + 2.2
        pages.append("<page width=\"595\" height=\"842\">" + "".join(words) + "</page>")
    return "".join(pages)


class BboxColumnTests(unittest.TestCase):
    def errors(self, generated, squeeze=()):
        text = gate.bbox_layout(bbox(generated, squeeze))
        return gate.comparison_errors(PRINTED, text, "en", {}, COUNTRIES)

    def test_bbox_text_reproduces_the_printed_columns(self):
        self.assertEqual([], self.errors(PRINTED))
        self.assertEqual([], self.errors(PRINTED + "\f" * 3))

    def test_column_squeezed_to_one_space_by_layout_stays_in_its_column(self):
        # The heading ends 11.5 pt before the operator: -layout prints one space
        # and merges them; the word positions keep them apart.
        self.assertEqual([], self.errors(PRINTED, squeeze={"GIBRALTAR"}))

    def test_squeeze_test_is_red_when_the_column_logic_is_broken(self):
        # Prove the test above can fail: a gap threshold wider than 11.5 pt
        # merges the squeezed cells again and the checker must report it.
        original = gate.COLUMN_GAP_PT
        gate.COLUMN_GAP_PT = 13.0
        try:
            errors = self.errors(PRINTED, squeeze={"GIBRALTAR"})
        finally:
            gate.COLUMN_GAP_PT = original
        self.assertTrue(any("GIBRALTAR" in error for error in errors), errors)

    def test_a_deleted_real_office_row_is_still_a_gap(self):
        damaged = PRINTED.replace(row("", "", "", "All destinations", "ZWXX"), "")
        errors = self.errors(damaged)
        self.assertTrue(any("ZIMBABWE: office name" in error for error in errors), errors)
        self.assertTrue(any("ZIMBABWE: office code" in error for error in errors), errors)

    def test_a_changed_operator_is_still_a_gap_with_squeezed_columns(self):
        damaged = PRINTED.replace("Printed operator", "Printed operatoX", 1)
        errors = self.errors(damaged, squeeze={"GIBRALTAR"})
        self.assertTrue(any("GIBRALTAR: network/ROA" in error for error in errors), errors)

    def test_note_runs_over_a_page_break_and_an_indented_example_stays_in_it(self):
        note = ["1) Where possible include the code. For example:",
                "         MELBOURNE(3000), BURWOOD(3125)", "\f" + HEADER,
                "         PERTHRADIO, SYDNEYRADIO", "2) Also valid elsewhere."]
        text = PRINTED.replace("1) " + NOTE, "1) " + NOTE + "\n" + "\n".join(note))
        rows = gate.layout_rows(text)
        self.assertEqual([], [r for r in rows if "PERTHRADIO" in r[0]], rows)
        self.assertTrue(any("PERTHRADIO" in r[5] for r in rows), rows)


class F32ContentTests(unittest.TestCase):
    def errors(self, text, source=PRINTED, countries=COUNTRIES):
        return gate.comparison_errors(source, text, "en", {}, countries)

    def test_printed_baseline_and_page_drift_are_preserved(self):
        self.assertEqual([], self.errors(PRINTED))
        self.assertEqual([], self.errors(PRINTED + "\f" * 47))

    def test_network_header_wrapped_over_two_lines_still_scopes_the_table(self):
        wrapped = "\n".join([
            row("Country /", "Network", "Network", "Name of", "Office"),
            row("Geographical Area", "(administration/ROA)", "code", "Telegraph Office", "code")])
        text = PRINTED.replace(HEADER, wrapped)
        self.assertEqual([], self.errors(text))
        self.assertEqual([], self.errors(text + "\f" * 3))
        damaged = text.replace("VU- -", "VQ- -")
        self.assertTrue(any("VANUATU: network code" in error for error in self.errors(damaged)))

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

    def test_blanked_office_name_is_still_reported_next_to_a_centred_heading(self):
        # Last office rows of one country, then the next country's label printed
        # one row below its network row: the office rows are not that country's.
        generated = "\n".join([
            HEADER,
            row("GIBRALTAR", "Printed operator", "GK- -"), row("GIBRALTAR"), row("GIBRALTAR"),
            row("", "", "", "Madeira", "GKMA"),
            row("", "", "", "All others", "GKXX"),
            row("", "Printed operator", "LU- -"), row("LUXEMBOURG"), row("LUXEMBOURG"),
            row("LUXEMBOURG", "", "", "All destinations", "LUXX"),
            country("VANUATU", "VU- -", NOTE), country("ZIMBABWE", "ZW- -")])
        printed = "\n".join([
            HEADER,
            row("GIBRALTAR", "Printed operator", "GK- -"), row("GIBRALTAR"), row("GIBRALTAR"),
            row("", "", "", "Madeira", "GKMA"),
            row("", "", "", "All others", "GKXX"),
            country("LUXEMBOURG", "LU- -"),
            country("VANUATU", "VU- -", NOTE), country("ZIMBABWE", "ZW- -")])
        self.assertEqual(self.errors(generated, source=printed), [])
        blanked = generated.replace(row("", "", "", "Madeira", "GKMA"), row("", "", "", "", "GKMA"))
        self.assertNotEqual(self.errors(blanked, source=printed), [])

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
