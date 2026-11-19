"""Public regressions for independent F.32 front matter/appendix preservation."""

import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "f32_sections.py"
SPEC = importlib.util.spec_from_file_location("f32_sections", SCRIPT)
sections = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sections)
FIXTURES = SCRIPT.parents[1] / "ituob/spec/fixtures/f32"


class F32SectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {}
        for language, suffix in (("en", ""), ("fr", "-F"), ("es", "-S")):
            cls.sources[language] = subprocess.run(
                ["pdftotext", "-layout", str(FIXTURES / f"official-2011{suffix}.pdf"), "-"],
                check=True, capture_output=True, text=True).stdout

    def errors(self, generated, language="en"):
        return sections.compare_sections(self.sources[language], generated, language)

    def test_complete_printed_sections_preserved_in_all_languages(self):
        for language, source in self.sources.items():
            with self.subTest(language=language):
                self.assertEqual([], self.errors(source, language))

    def test_paragraph_labels_line_wrapping_and_page_furniture_are_presentation(self):
        source = self.sources["en"]
        generated = re.sub(r"^(\s*)([1-5])\.\s+", lambda m: m[1] + chr(96+int(m[2])) + ") ", source, flags=re.M)
        # Move only prose wrapping; table column geometry remains meaningful.
        generated = generated.replace("TSB announced the approval of ITU-T\nRecommendation", "TSB announced the approval of\nITU-T Recommendation")
        generated = generated.replace("Annex to ITU OB 980-E", "Annex to ITU OB No. 32-E")
        self.assertEqual([], self.errors(generated))

    def test_every_tsb_paragraph_tail_is_required(self):
        for language, source in self.sources.items():
            front = sections._parts(source)[0]
            for number, paragraph in enumerate(sections._paragraphs(front), 1):
                # Delete a substantive suffix inside the extracted paragraph.
                damaged = source.replace(paragraph, paragraph[:-30], 1)
                self.assertNotEqual(source, damaged)
                with self.subTest(language=language, paragraph=number):
                    self.assertTrue(self.errors(damaged, language))

    def test_missing_tsb_paragraph_cannot_be_replaced_in_appendix(self):
        source = self.sources["en"]
        paragraph = sections._paragraphs(sections._parts(source)[0])[2]
        damaged = source.replace(paragraph, "", 1) + paragraph
        self.assertTrue(self.errors(damaged))

    def test_appendix1_network_code_is_required_in_its_column(self):
        source = self.sources["en"]
        start = source.index("Appendix 1")
        before, appendix = source[:start], source[start:]
        damaged = before + appendix.replace("SJ             JP", "XX             JP", 1)
        self.assertNotEqual(source, damaged)
        self.assertTrue(any("appendix 1 network codes" in e for e in self.errors(damaged)))

    def test_appendix1_generated_layout_wraps_header_and_roa_text(self):
        # Table header over two lines; "– Telkom SA" ends in the code column
        # without being a network code; a code may follow a dash ("– NU").
        text = "\n".join([
            "         Country /          Network       Network             Special origin indicator",
            "     geographical area (administration/ROA) code",
            "ARABIE SAOUDITE            GOVT –      SJ                JP",
            "SAUDI ARABIA               Ministry of",
            "ARABIA SAUDITA             Communications",
            "NICARAGUA                  Nicatelsat – NU                XQ",
            "NICARAGUA                  Compañía",
            "NICARAGUA                  Nicaragüense",
            "SUDAFRICAINE (RÉP.)        Telkom SA       SA            SV",
            "SOUTH AFRICA               – Telkom SA                   XQ",
            "SUDAFRICANA (REP.)         Ltd, Pretoria",
        ])
        columns = sections._appendix1(text, strict=False)
        self.assertEqual("SJ NU SA", columns[2])
        self.assertEqual(["SJ", "NU", "SA"], list(columns[4]))
        self.assertEqual("SV XQ", " ".join(columns[4]["SA"]["origin indicators"]))
        self.assertIn("– Telkom SA", columns[4]["SA"]["network/ROA"])
        self.assertEqual("SUDAFRICAINE (RÉP.)", columns[4]["SA"]["country"])

    def test_appendix3_repeated_form_header_is_one_heading(self):
        form = ["4.1.      AMENDMENTS", "       Amendment No.        Operational        Country",
                "                            Bulletin No."]
        one_page = "\n".join(form + ["1", "2", "3"])
        paged = "\n".join(form + ["1", "2", "Annex to ITU OB No. 32-E  – 71 –"] + form[1:] + ["3"])
        self.assertEqual(sections._appendix3(one_page)[1], sections._appendix3(paged)[1].replace(
            "Annex to ITU OB No. 32-E  – 71 –\n", ""))

    def test_appendix1_origin_indicator_order_is_preserved(self):
        source = self.sources["en"]
        start = source.index("Appendix 1")
        appendix = source[start:]
        damaged = source[:start] + appendix.replace("SV\n", "XX\n", 1)
        self.assertNotEqual(source, damaged)
        self.assertTrue(any("origin indicators" in e for e in self.errors(damaged)))

    def test_indicator_cannot_move_to_another_network_with_same_global_order(self):
        source = self.sources["en"]
        start = source.index("Appendix 1")
        appendix = source[start:].replace("SJ             JP", "SJ               ", 1)
        appendix = appendix.replace("AA             SV", "AA             JP SV", 1)
        damaged = source[:start] + appendix
        self.assertNotEqual(source, damaged)
        self.assertTrue(any("network SJ origin indicators" in e for e in self.errors(damaged)))

    def test_appendix_titles_and_column_labels_are_required(self):
        source = self.sources["en"]
        for old, new, label in (
                ("Special Origin Indicators for the Telegram Retransmission System", "Origin Indicators", "appendix 1 title"),
                ("Special origin indicator", "Origin indicator", "appendix 1 column headings"),
                ("Countries or geographical areas for which information", "Countries for which information", "appendix 3 title"),
                ("AMENDMENTS", "ENMIENDAS", "amendments heading")):
            with self.subTest(label=label):
                damaged = source.replace(old, new)
                self.assertNotEqual(source, damaged)
                self.assertTrue(any(label in e for e in self.errors(damaged)))

    def test_appendix1_roa_cannot_cross_network_boundary(self):
        source = self.sources["en"]
        lines = source.splitlines(keepends=True)
        start = next(i for i, line in enumerate(lines) if "Appendix 1" in line)
        row = next(i for i in range(start, len(lines)) if "Matrix Omni" in lines[i])
        code = lines[row].index("AA")
        lines[row] = lines[row][:code] + "  " + lines[row][code+2:]
        lines[row+1] = lines[row+1][:code] + "AA" + lines[row+1][code+2:]
        damaged = "".join(lines)
        before = sections._appendix1(sections._parts(source)[1])
        after = sections._appendix1(sections._parts(damaged)[1])
        self.assertEqual(before[:4], after[:4])
        self.assertTrue(any("network AA network/ROA" in e for e in self.errors(damaged)))

    def test_appendix2_organization_cannot_cross_code_boundary(self):
        source = self.sources["en"]
        damaged = source.replace("    XB         Inter-American", "               Inter-American", 1)
        damaged = damaged.replace("               Fonds des Nations Unies pour l'enfance",
                                  "    XB         Fonds des Nations Unies pour l'enfance", 1)
        before = sections._appendix2(sections._parts(source)[2])
        after = sections._appendix2(sections._parts(damaged)[2])
        self.assertEqual([sections._norm(value) for value in before[:2]],
                         [sections._norm(value) for value in after[:2]])
        self.assertTrue(any("appendix 2 network XB organizations" in e for e in self.errors(damaged)))

    def test_appendix2_organization_order_and_full_names_are_preserved(self):
        source = self.sources["en"]
        damaged = source.replace("Inter-American Development Bank", "Development Bank", 1)
        self.assertTrue(any("appendix 2 organizations" in e for e in self.errors(damaged)))

    def test_appendix3_country_cannot_move_to_another_bulletin(self):
        source = self.sources["en"]
        damaged = source.replace("906     Thailand", "906     Malta").replace("919     Malta", "919     Thailand")
        self.assertNotEqual(source, damaged)
        self.assertTrue(any("appendix 3 cessation list" in e for e in self.errors(damaged)))

    def test_amendments_form_requires_all_thirty_ordered_rows(self):
        for language, source in self.sources.items():
            damaged, count = re.subn(r"^\s*30\s*$", "", source, flags=re.M)
            self.assertEqual(1, count)
            with self.subTest(language=language):
                self.assertTrue(any("amendments form" in e for e in self.errors(damaged, language)))

    def test_missing_appendix_fails_with_a_diagnostic(self):
        source = self.sources["en"]
        self.assertTrue(any("missing appendix" in e for e in self.errors(source.replace("Appendix 2", "Deleted"))))


if __name__ == "__main__":
    unittest.main()
