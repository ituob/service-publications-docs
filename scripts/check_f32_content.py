#!/usr/bin/env python3
"""Fail closed on lost F.32 cessation notes, network codes or country order.

The independent fixture records printed content, rather than accepting whatever
the provider currently returns. Page drift is reported but never grants a content
exception. Run against the three generated PDFs with --generated DIRECTORY.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


FIXTURE = Path(__file__).resolve().parents[1] / "ituob/spec/fixtures/f32/printed-content.json"
LANGUAGES = {"E": "en", "F": "fr", "S": "es"}


def normalize(text):
    return re.sub(r"[\W_]", "", text.lower())


def content_errors(text, language, expected):
    # All editions keep the three printed country names. Exclude the appendices,
    # which repeat countries and must not mask missing destination content.
    destination = re.split(r"Appendix\s+1\s*:", text, maxsplit=1)[0]
    normalized = normalize(destination)
    errors = []
    for note in expected["notes"]:
        if normalize(note[language]) not in normalized:
            errors.append(f"missing complete note from official page {note['page']}: {note[language]}")

    # With -layout, adjacent columns interleave wrapped country names. Retain
    # each line's first cell so a ROA name cannot interrupt a country heading.
    country_text = "\n".join(re.split(r"\s{2,}", line.strip(), maxsplit=1)[0]
                             for line in destination.splitlines())
    previous = -1
    for country in expected["countries"]:
        pattern = r"\s+".join(re.escape(word) for word in country.split())
        match = re.search(pattern, country_text)
        if match is None:
            errors.append(f"missing country: {country}")
        elif match.start() <= previous:
            errors.append(f"country out of printed order: {country}")
        else:
            previous = match.start()

    for code in expected["network_codes"]:
        if not re.search(rf"\b{code}\s*-\s*-", destination):
            errors.append(f"missing network code cell: {code}- -")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, required=True)
    args = parser.parse_args()
    expected = json.loads(FIXTURE.read_text())
    failed = False
    for suffix, language in LANGUAGES.items():
        name = f"F.32-2011-{suffix}.pdf"
        paths = list(args.generated.rglob(name))
        if len(paths) != 1:
            print(f"FAIL {name}: expected one PDF, found {len(paths)}", file=sys.stderr)
            failed = True
            continue
        result = subprocess.run(["pdftotext", "-layout", str(paths[0]), "-"],
                                check=True, capture_output=True, text=True)
        errors = content_errors(result.stdout, language, expected)
        pages = result.stdout.count("\f")
        print(f"{name}: {pages} pages (official English: 47); "
              f"{len(expected['notes']) - sum(e.startswith('missing complete note') for e in errors)}/35 complete notes; "
              f"{'FAIL' if errors else 'PASS'}")
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        failed |= bool(errors)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
