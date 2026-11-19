#!/usr/bin/env python3
"""Compare the printed F.32 sections with the pinned official publication.

Comparison is scoped to countries and ordered column streams, never a global bag
of substrings. Running furniture, line wrapping and punctuation are immaterial.
"""

import argparse
from collections import Counter
from difflib import SequenceMatcher
import json
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import unicodedata
import xml.etree.ElementTree as ET

try:
    from f32_sections import difference_ops
except ModuleNotFoundError:
    from scripts.f32_sections import difference_ops

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "ituob/spec/fixtures/f32/printed-content.json"
OFFICIAL = ROOT / "ituob/spec/fixtures/f32/official-2011.pdf"
LANGUAGES = {"E": "en", "F": "fr", "S": "es"}
COLUMN_NAMES = ("country/qualifier", "network/ROA", "network code", "office name", "office code", "notes", "row association")


# Footnote reference marks ("2)") are superscripts: pdftotext attaches them to
# whichever neighbouring column their baseline happens to fall in, in either
# PDF. They are compared per country as a multiset instead of per column.
MARKER = re.compile(r"\d+\)")


def normalize(text):
    return re.sub(r"[\W_]", "", text.lower())


def _plain(text):
    return text.replace("\u00ad", "")


def heading_normalize(text):
    return normalize(re.sub(r"\d+\)", "", text))


def canonical(text):
    """Ignore reflow and typographic quotes/dashes, retain content punctuation."""
    text = MARKER.sub("", unicodedata.normalize("NFKC", text).lower())
    text = text.translate(str.maketrans({"’": "'", "‘": "'", "“": '"', "”": '"',
                                       "–": "-", "—": "-", "\u00ad": ""}))
    text = text.translate(str.maketrans({"\u2192": ">", "\u27f6": ">"}))
    return re.sub(r"[\s-]+", "", text)


def source_path(language="en"):
    suffix = {"en": "", "fr": "-F", "es": "-S"}[language]
    return OFFICIAL.with_name(f"official-2011{suffix}.pdf")


def official_countries(language="en"):
    """Read country labels from positioned print, not from seed/replay data."""
    document = ET.parse(OFFICIAL.with_suffix(".xml"))
    fonts = {font.get("id"): font.attrib for font in document.iter("fontspec")}
    rules = (ROOT / "catalogs/f32_seed_contexts.yaml").read_text()
    layouts = {first: list(map(int, counts.split(","))) for first, counts in
               re.findall(r"- first: (.+)\n    lines: \[([^]]+)\]", rules)}
    headings = []
    for page in document.iter("page"):
        if int(page.get("number")) < 3:
            continue
        if any(re.search(r"(?:Appendix|Appendice|Apéndice)\s+1", "".join(cell.itertext()))
               for cell in page.findall("text")):
            break
        grouped = {}
        for cell in page.findall("text"):
            font = fonts[cell.get("font")]
            value = "".join(cell.itertext()).strip()
            if (value and int(cell.get("left")) < 225
                    and 145 < int(cell.get("top")) < 1180
                    and "Bold" in font["family"] and int(font["size"]) >= 10):
                top = int(cell.get("top"))
                baseline = next((key for key in grouped if abs(key - top) <= 2), top)
                grouped.setdefault(baseline, []).append((int(cell.get("left")), value))
        for _, cells in sorted(grouped.items()):
            headings.append(re.sub(r"\d+\)", "", " ".join(value for _, value in sorted(cells))))
    countries = []
    while headings:
        counts = layouts.get(headings[0], [1, 1, 1])
        if len(headings) < sum(counts):
            raise ValueError("incomplete official country heading")
        parts = []
        for count in counts:
            parts.append(" ".join(headings[:count]))
            del headings[:count]
        # A country repeated at a page boundary is continuation furniture.
        if not countries or normalize(parts[1]) != normalize(countries[-1][1]):
            countries.append(parts)
    return countries


HEADER_LABELS = ("Network (administration/ROA)", "Réseau (administration/ER)", "Red (administración/EER)")
WRAPPED_LABELS = ("(administration/ROA)", "(administration/ER)", "(administración/EER)")


def _is_header(line):
    """The network column header, on one line or wrapped over two (the label's second line)."""
    return any(label in line for label in HEADER_LABELS + WRAPPED_LABELS)


def layout_rows(text):
    """Keep all destination ink in its printed column or full-width note."""
    rows = []
    cuts = None
    started = False
    in_note = False
    lines = text.replace("\f", "\n<page>\n").splitlines()
    for line_index, raw in enumerate(lines):
        if re.search(r"(?:^|\s)(?:Appendix|Appendice|Apéndice)\s+1\s*:?(?:\s|$)", raw):
            break
        header = _is_header(raw)
        if raw == "<page>" or header:
            following_lines = []
            for following in lines[line_index + 1:]:
                if following == "<page>" or _is_header(following):
                    break
                following_lines.append(following)
            starts = Counter(chunk.start() for following in following_lines
                             for chunk in re.finditer(r"\S(?:.*?\S)?(?= {2,}|$)", following))
            networks = Counter(match.start(1) for following in following_lines
                               for match in re.finditer(r"(?:^| {2,})([A-Z]{2}\s*-\s*-)", following))
            codes = Counter(match.start(1) for following in following_lines
                            for match in re.finditer(r"(?:^| {2,})((?:[A-Z]{4}|--[A-Z]{2}))\s*$", following))
            if header or (started and codes):
                if header:
                    if not any(label in raw for label in HEADER_LABELS):
                        # Wrapped header: the column names sit on the line above.
                        top = [m.start() for m in re.finditer(r"\S(?:.*?\S)?(?= {2,}|$)", lines[line_index - 1])]
                        defaults = top[1:5] if len(top) >= 5 else [raw.index("("), 0, 0, 0]
                    elif "Réseau (administration/ER)" in raw:
                        defaults = [raw.index("Réseau"), raw.index("Code de"), raw.index("Nom du bureau"), raw.rindex("Code de")]
                    elif "Red (administración/EER)" in raw:
                        defaults = [raw.index("Red ("), raw.index("Código de red"), raw.index("Nombre de la oficina"), raw.rindex("Código")]
                    else:
                        defaults = [raw.index(label) for label in
                                    ("Network (administration/ROA)", "Network code",
                                     "Name of Telegraph Office", "Office code")]
                    started = True
                else:
                    defaults = [cut + 1 for cut in cuts[1:5]]
                office_code = codes.most_common(1)[0][0] if codes else defaults[3]
                if networks:
                    network = networks.most_common(1)[0][0]
                elif not header and codes:
                    # A continuation page with no network code: pdftotext drops the
                    # unused left margin, so the previous page's cuts are stale.
                    # Anchor the name column on the page's own data instead.
                    code_at = codes.most_common(1)[0][0]
                    names = Counter(x for x in starts if 0 < x < code_at - 6)
                    network = (max(names, key=lambda x: (names[x], -x)) - 8) if names else defaults[1]
                    if names:
                        defaults[0] = network - 8
                else:
                    network = defaults[1]
                office_candidates = [x for x in starts if network + 3 <= x < office_code - 6]
                office = max(office_candidates, key=lambda x: starts[x]) if office_candidates else defaults[2]
                roa_candidates = [x for x in starts if 15 <= x < min(network - 8, office - 10)]
                roa = max(roa_candidates, key=lambda x: starts[x]) if roa_candidates else defaults[0]
                cuts = [0, roa - 1, network - 1, office - 1, office_code - 1, 1000]
            if header:
                in_note = False
            continue
        if not started or not raw.strip():
            continue
        value = raw.strip()
        if (re.search(r"(?:Annex to ITU OB|Annexe au BE|Anexo al BE)", value) or "15.V.2011" == value
                or any(title in value for title in ("Destination Indicators (DI) assigned", "Indicateurs de destination (ID) attribués", "Indicadores de destino (ID) atribuidos"))
                or value in ("réseau", "bureau")
                or "Service Publication Annex" in value
                or re.fullmatch(r"[–—-]?\s*\d+\s*[–—-]?", value)
                or re.fullmatch(r"1\s+2\s+3\s+4\s+5", value)
                or re.fullmatch(r"[_–—-]+", value)):
            continue
        # Notes are printed full width, and may have the marker on its own line.
        if re.match(r"^ {0,7}\d+\)(?:\s|$)", raw):
            in_note = True
        cells = [""] * 5
        anchors = [0] + [cut + 1 for cut in cuts[1:5]]
        for chunk in re.finditer(r"\S(?:.*?\S)?(?= {2,}|$)", raw):
            column = min(range(5), key=lambda number: abs(chunk.start() - anchors[number]))
            cells[column] += (" " if cells[column] else "") + chunk.group()
        if in_note:
            # A new heading/table row terminates a note even without a blank.
            if (re.search(r"[A-Z]{2}\s*-\s*-", cells[2])
                    or (cells[0] and cells[0].upper() == cells[0]
                        and re.search(r"[A-ZÀ-Ý]{3}", cells[0])
                        and not re.match(r"^\d+\)", cells[0])
                        # A wrapped date ("1.XII.2008") is not a country heading.
                        and not re.fullmatch(r"[\d.IVXL]+", cells[0]))):
                in_note = False
            else:
                rows.append(["", "", "", "", "", _plain(value)])
                continue
        rows.append([_plain(cell) for cell in cells] + [""])
    return rows


def expand_relative_codes(rows):
    """Resolve a relative office code ("--AC") against its network ("PH- -").

    The official print abbreviates the office code to its two-letter suffix; the
    rendering may print the full indicator ("PHAC"). They name the same office.
    """
    network = ""
    result = []
    for row in rows:
        if not row[5]:
            found = re.search(r"\b([A-Z]{2})(?:\s*-){0,2}(?:\s*\d+\))?$", row[2])
            if found:
                network = found[1]
            code = re.fullmatch(r"\s*-{1,2}([A-Z]{2})(\s*\d+\))?\s*", row[4])
            if code and network:
                row = row[:4] + [network + code[1] + (code[2] or "")] + row[5:]
        result.append(row)
    return result


def _country_sections(text, countries):
    rows = layout_rows(text)
    def key(value):
        plain = unicodedata.normalize("NFKD", heading_normalize(value))
        return "".join(char for char in plain if not unicodedata.combining(char))

    boundaries = []
    errors = []
    cursor = 0
    for aliases in countries:
        signature = key(aliases[1])
        found = None
        finish = None
        for index in range(cursor, len(rows)):
            if not rows[index][0]:
                continue
            combined = ""
            for last in range(index, min(len(rows), index + 8)):
                combined += key(rows[last][0])
                if (combined == signature or signature in combined
                        or (len(combined) >= 10 and signature.startswith(combined))
                        or (len(combined) >= 10 and SequenceMatcher(None, combined, signature).ratio() >= 0.94)):
                    found, finish = index, last
                    break
                if not signature.startswith(combined):
                    break
            if found is not None:
                break
        if found is None:
            errors.append(f"missing/out-of-order country heading: {aliases[1]}")
            continue
        start = found
        # Include the preceding French heading when its spelling is distinct.
        french = key(aliases[0])
        if not french.startswith(signature) and found > cursor:
            for before in range(found - 1, max(cursor - 1, found - 5), -1):
                candidate = key(" ".join(row[0] for row in rows[before:found]))
                if candidate == french:
                    start = before
                    break
        # In generated tables vertically centered country labels can follow the
        # first network row. Move only to that adjacent row, not earlier offices.
        for before in range(start - 1, max(-1, start - 5), -1):
            if rows[before][0] or rows[before][5]:
                break
            if re.search(r"[A-Z]{2}\s*-", rows[before][2]):
                start = before
                if before > 0 and rows[before - 1][1] and not any(rows[before - 1][i] for i in (0, 2, 3, 4, 5)):
                    start -= 1
                break
        boundaries.append((aliases[1], start))
        cursor = finish + 1
    sections = {}
    markers = {}
    if boundaries and boundaries[0][1] > 0:
        errors.append("unassigned destination content before first country")
    for number, (country, start) in enumerate(boundaries):
        end = boundaries[number + 1][1] if number + 1 < len(boundaries) else len(rows)
        section_rows = expand_relative_codes(rows[start:end])
        markers[country] = sorted(mark for row in section_rows for cell in row
                                  for mark in MARKER.findall(cell))
        runs = []
        for row in section_rows:
            if not any(canonical(cell) for cell in row):
                continue
            kind = "note" if row[5] else "table"
            if not runs or runs[-1][0] != kind:
                runs.append((kind, [""] * 7))
            for column, cell in enumerate(row):
                runs[-1][1][column] += " " + cell
        # The two code streams alone do not prove row ownership: moving a
        # network code past an office row can leave both streams unchanged.
        current_network = ""
        office_names = ""
        associations = []
        for row in section_rows:
            if row[5]:
                continue
            network = re.search(r"\b([A-Z]{2})(?:\s*-){0,2}(?:\s*\d+\))?$", row[2])
            if network:
                current_network = network[1]
            office_names += " " + row[3]
            if re.search(r"(?:[A-Z]{4}|--[A-Z]{2})", row[4]):
                associations.append(f"[{current_network}|{row[4]}|{canonical(office_names)}]")
        if runs:
            runs[0][1][6] = " ".join(associations)
        sections[country] = runs
    return sections, errors, markers


def country_sections(text, countries):
    sections, errors, _ = _country_sections(text, countries)
    return sections, errors


def comparison_errors(official_text, generated_text, language, expected, countries=None):
    countries = countries if countries is not None else official_countries(language)
    official, source_errors, official_marks = _country_sections(official_text, countries)
    generated, errors, generated_marks = _country_sections(generated_text, countries)
    errors = ["official extraction: " + error for error in source_errors] + errors
    for country, source in official.items():
        if country not in generated:
            continue
        actual_runs = generated[country]
        if [kind for kind, _ in source] != [kind for kind, _ in actual_runs]:
            errors.append(f"{country}: ordered table/note placement differs "
                          f"(official {[kind for kind, _ in source]}, "
                          f"generated {[kind for kind, _ in actual_runs]})")
        # Also compare complete streams when placement differs so every missing
        # printed sequence still contributes an actionable country/column gap.
        source_columns = [" ".join(cells[column] for _, cells in source) for column in range(7)]
        actual_columns = [" ".join(cells[column] for _, cells in actual_runs) for column in range(7)]
        groups = [("", source_columns, actual_columns)]
        if len(source) == len(actual_runs) and len(source) > 1:
            groups.extend((f" block {index + 1}", cells, actual_runs[index][1])
                          for index, (_, cells) in enumerate(source))
        for block, source_cells, actual_cells in groups:
            for column, printed in enumerate(source_cells):
                wanted = canonical(printed)
                actual = canonical(actual_cells[column])
                if wanted != actual:
                    differences = difference_ops(wanted, actual)
                    first = differences[0]
                    _, a, b, c, d = first
                    errors.append(f"{country}{block}: {COLUMN_NAMES[column]} ordered content differs "
                                  f"({len(differences)} gaps; official {len(wanted)} / generated {len(actual)} characters); "
                                  f"official …{wanted[max(0,a-35):min(len(wanted),b+60)]}…; "
                                  f"generated …{actual[max(0,c-35):min(len(actual),d+60)]}…")
    # A superscript printed on the line above its row can land on either side of
    # a country boundary, so the marks are compared over the whole table.
    official_all = Counter(mark for marks in official_marks.values() for mark in marks)
    generated_all = Counter(mark for marks in generated_marks.values() for mark in marks)
    if official_all != generated_all:
        where = [country for country in official_marks
                 if Counter(official_marks[country]) != Counter(generated_marks.get(country, []))]
        errors.append(f"footnote reference marks differ: missing {dict(official_all - generated_all)}, "
                      f"extra {dict(generated_all - official_all)} "
                      f"(countries with different counts: {', '.join(where[:12])})")
    return errors


def content_errors(text, language, expected):
    """Compatibility entry point; source evidence always comes from the PDF."""
    return comparison_errors(official_text(language), text, language, expected)


def official_text(language="en"):
    path = source_path(language)
    manifest = json.loads((OFFICIAL.parent / "official-sources.json").read_text())
    suffix = {"en": "E", "fr": "F", "es": "S"}[language]
    if hashlib.sha256(path.read_bytes()).hexdigest() != manifest[suffix]["sha256"]:
        raise ValueError(f"official {suffix} PDF does not match the pinned source")
    # Keep the independent source read distinct from replayed generated output.
    with subprocess.Popen(["pdftotext", "-layout", str(path), "-"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
        output, error = process.communicate()
        if process.returncode:
            raise RuntimeError(f"official PDF extraction failed: {error}")
        return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, required=True)
    args = parser.parse_args()
    expected = json.loads(FIXTURE.read_text())
    failed = False
    for suffix, language in LANGUAGES.items():
        source = official_text(language)
        countries = official_countries(language)
        name = f"F.32-2011-{suffix}.pdf"
        paths = list(args.generated.rglob(name))
        if len(paths) != 1:
            print(f"FAIL {name}: expected one PDF, found {len(paths)}", file=sys.stderr)
            failed = True
            continue
        result = subprocess.run(["pdftotext", "-layout", str(paths[0]), "-"],
                                check=True, capture_output=True, text=True)
        errors = comparison_errors(source, result.stdout, language, expected, countries)
        try:
            from f32_sections import compare_sections
            errors.extend(compare_sections(source, result.stdout, language))
        except ModuleNotFoundError:
            from scripts.f32_sections import compare_sections
            errors.extend(compare_sections(source, result.stdout, language))
        print(f"{name}: {result.stdout.count(chr(12))} pages; "
              f"{len(countries)} official country sections; {len(errors)} content gaps; "
              f"{'FAIL' if errors else 'PASS'}")
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        failed |= bool(errors)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
