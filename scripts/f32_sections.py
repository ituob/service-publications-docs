"""Independent, ordered comparisons of F.32 front matter and appendices.

Inputs are same-language pdftotext -layout output from official and rendered PDFs.
Page counts and line wrapping are deliberately not content boundaries.
"""

from difflib import SequenceMatcher
import re
import unicodedata


APPENDIX = r"(?:Appendix|Appendice|Apéndice)"


def _norm(text):
    return re.sub(r"[\W_]", "", unicodedata.normalize("NFC", text).lower())


def _clean(text):
    lines = []
    for line in text.replace("\f", "\n").splitlines():
        if (re.search(r"(?:Annex to ITU OB|Annexe au BE|Anexo al BE)", line)
                or line.strip() == "15.V.2011"
                or re.fullmatch(r"\s*[–—-]\s*\d+\s*[–—-]\s*", line)):
            continue
        lines.append(line)
    return "\n".join(lines)


def _difference(label, wanted, actual):
    wanted, actual = _norm(wanted), _norm(actual)
    if wanted == actual:
        return []
    changes = [op for op in SequenceMatcher(None, wanted, actual, autojunk=False).get_opcodes()
               if op[0] != "equal"]
    _, a, b, c, d = changes[0]
    return [f"{label}: ordered content differs ({len(changes)} gaps; "
            f"official {len(wanted)} / generated {len(actual)} characters); "
            f"official …{wanted[max(0,a-25):min(len(wanted),b+45)]}…; "
            f"generated …{actual[max(0,c-25):min(len(actual),d+45)]}…"]


def _parts(text):
    text = _clean(text)
    starts = [re.search(rf"{APPENDIX}\s+{n}\b", text) for n in (1, 2, 3)]
    if any(match is None for match in starts):
        raise ValueError("missing appendix 1, 2 or 3 heading")
    positions = [text.rfind("\n", 0, match.start()) + 1 for match in starts]
    if positions != sorted(positions):
        raise ValueError("appendices are out of order")
    return text[:positions[0]], text[positions[0]:positions[1]], text[positions[1]:positions[2]], text[positions[2]:]


def _paragraphs(front):
    heading = re.search(r"(?:Note from TSB|Note du TSB|Nota de la TSB)", front)
    if not heading:
        raise ValueError("missing TSB note heading")
    text = front[heading.end():]
    # Stop at the semantic destination table heading, irrespective of page.
    end = re.search(r"^.*(?:Destination Indicators \(DI\)|Indicateurs de destination \(ID\)|Indicadores de destino \(ID\)|Country\s*/|Pays\s*/|País\s*/)", text, re.M)
    if end:
        text = text[:end.start()]
    matches = list(re.finditer(r"^\s*(?:([1-5])\.|([a-e])\))\s+", text, re.M))
    if len(matches) != 5:
        raise ValueError(f"expected five TSB paragraphs, found {len(matches)}")
    numbers = [int(m[1]) if m[1] else ord(m[2]) - ord('a') + 1 for m in matches]
    if numbers != [1, 2, 3, 4, 5]:
        raise ValueError("TSB paragraphs are out of order")
    paragraphs = [text[m.end():matches[i+1].start() if i < 4 else len(text)] for i, m in enumerate(matches)]
    # Printed publication/table titles after paragraph 5 are outside the note.
    paragraphs[-1] = re.split(r"\n\s*\n", paragraphs[-1].strip(), maxsplit=1)[0]
    return paragraphs


def _appendix1(text):
    columns = [[], [], [], []]
    networks = {}
    active = None
    country = ""
    alias_count = 0
    for chunk in re.split(r"(?=^.*(?:Country\s*/|Pays\s*/|País\s*/))", text, flags=re.M):
        lines = chunk.splitlines()
        header = next((i for i, line in enumerate(lines)
                       if re.search(r"Country\s*/|Pays\s*/|País\s*/", line)), None)
        if header is None:
            continue
        # Column starts come from actual two-letter network/indicator cells;
        # headings are centered differently in each edition.
        candidates = []
        for line in lines[header + 1:]:
            for match in re.finditer(r"\b([A-Z]{2})\s{2,}([A-Z]{2})(?:\s|$)", line):
                if match.start() > len(lines[header]) * .4:
                    candidates.append((match.start(1), match.start(2)))
        if not candidates:
            raise ValueError("appendix 1 has no network/indicator cells")
        code, indicator = min(candidates)
        body = lines[header + 1:]
        continuation = next((i for i, line in enumerate(body) if re.search(rf"{APPENDIX}\s+1\b", line)), len(body))
        body = body[:continuation]
        country_cut = min((m.end() for line in body
                           if (m := re.match(r"^\S.*?\s{2,}(?=\S)", line))
                           and m.end() < code), default=code // 2)
        started = False
        for line in body:
            if re.search(r"[A-Z]{2}", line[code:indicator]):
                started = True
            if not started and re.fullmatch(r"[A-Z ]+", line[indicator:].strip()) and line[indicator:].strip():
                started = True
            if not started:
                continue
            if (not line.strip() or re.fullmatch(r"[\d\s]+", line)
                    or re.search(rf"{APPENDIX}\s+1\b|Special Origin Indicators|Indicateur spécial|Indicador especial|Indicadores especiales", line, re.I)):
                continue
            country_value = line[:country_cut].strip()
            if country_value:
                if alias_count % 3 == 0:
                    country = country_value
                alias_count += 1
            code_value = line[code:indicator].strip()
            is_code = bool(re.fullmatch(r"[A-Z]{2}", code_value))
            if is_code:
                active = code_value
                if active in networks:
                    raise ValueError(f"appendix 1 duplicate network {active}")
                networks[active] = {"country": country, "network/ROA": [], "origin indicators": []}
            values = (line[:country_cut], line[country_cut:code if is_code else indicator],
                      code_value if is_code else "", line[indicator:])
            for i, value in enumerate(values):
                if value.strip():
                    columns[i].append(value.strip())
            if active and values[1].strip():
                networks[active]["network/ROA"].append(values[1].strip())
            if active and values[3].strip():
                networks[active]["origin indicators"].append(values[3].strip())
    if not columns[2]:
        raise ValueError("appendix 1 table missing")
    # Official continuation pages repeat complete trilingual country headings.
    aliases = columns[0]
    if len(aliases) % 3:
        raise ValueError("appendix 1 incomplete trilingual country heading")
    groups = [aliases[i:i+3] for i in range(0, len(aliases), 3)]
    columns[0] = [" ".join(group) for i, group in enumerate(groups) if i == 0 or group != groups[i-1]]
    return [" ".join(column) for column in columns] + [networks]


def _appendix2(text):
    lines = text.splitlines()
    header = next((i for i, line in enumerate(lines) if re.search(r"Network code|Code de|Código", line)), None)
    if header is None:
        raise ValueError("appendix 2 table header missing")
    codes, organizations = [], []
    records = {}
    pending = []
    active = None

    def flush():
        nonlocal pending, active
        if active is not None:
            if active in records:
                raise ValueError(f"appendix 2 duplicate network {active}")
            records[active] = " ".join(pending)
            pending = []
            active = None

    for line in lines[header+1:]:
        if not line.strip():
            flush()
            continue
        if re.fullmatch(r"[\d\s]+", line) or line.strip().lower() in ("réseau", "red"):
            continue
        match = re.match(r"^\s*(X[A-Z])\s+", line)
        if match:
            flush()
            active = match[1]
            codes.append(active)
            line = line[match.end():]
        organizations.append(line)
        pending.append(line)
    flush()
    return " ".join(codes), " ".join(organizations), records


def _appendix3(text):
    form = re.search(r"AMENDMENTS|AMENDEMENTS|ENMIENDAS|Appendix 3 amendments form", text, re.I)
    if not form:
        raise ValueError("appendix 3 amendments form missing")
    before, after = text[:form.start()], text[form.end():]
    # The official list is printed in two independent columns, read down each.
    left, right = [], []
    for line in before.splitlines():
        match = re.match(r"^\s*(\d{3})\s+(.+?)\s+(\d{3})\s+(.+?)\s*$", line)
        if match:
            left.append(match[1] + " " + match[2])
            right.append(match[3] + " " + match[4])
        elif re.match(r"^\s*\d{3}\s+", line):
            left.append(line.strip())
    # Keep all form column labels and the complete ordered 1..30 sequence.
    after = re.sub(r"^\s*[\d.]+\.\s*", "", after)
    return " ".join(left + right), after, form[0]


def _heading(text, number):
    """Read the first printed title and column labels, joining wrapped labels."""
    lines = text.splitlines()
    marker = next(i for i, line in enumerate(lines) if re.search(rf"{APPENDIX}\s+{number}\b", line))
    title_lines = [re.sub(rf"^.*?{APPENDIX}\s+{number}\s*:?[ \t]*", "", lines[marker])]
    header_pattern = (r"Country\s*/|Pays\s*/|País\s*/" if number == 1 else
                      r"Network code|Code de|Código" if number == 2 else
                      r"^\s*(?:OB No\.|BE No\.|BE N|Operational Bulletin No\.|Boletín de Explotación N|Bulletin d'exploitation N)")
    header = next((i for i in range(marker+1, len(lines)) if re.search(header_pattern, lines[i])), None)
    if header is None:
        raise ValueError(f"appendix {number} column headings missing")
    title_lines.extend(lines[marker+1:header])
    first = list(re.finditer(r"\S.*?(?=\s{2,}|$)", lines[header]))
    columns = [[match[0]] for match in first]
    centers = [(match.start()+match.end())/2 for match in first]
    for line in lines[header+1:]:
        if re.fullmatch(r"[\d\s]*", line):
            continue
        if re.search(r"[A-Z]{2}\s{2,}[A-Z]{2}", line) or re.match(r"^\s*(?:X[A-Z]|\d{3})\s+", line):
            break
        # Organization names precede the vertically centered first network code.
        if number == 2 and len(line.strip()) > 12 and not re.fullmatch(r"\s*(?:réseau|red)\s*", line):
            break
        for match in re.finditer(r"\S.*?(?=\s{2,}|$)", line):
            center = (match.start()+match.end())/2
            index = min(range(len(centers)), key=lambda n: abs(centers[n]-center))
            columns[index].append(match[0])
    labels = [" ".join(column) for column in columns]
    # The official cessation list repeats the same labels above its right half.
    if number == 3 and len(labels) == 4 and labels[:2] == labels[2:]:
        labels = labels[:2]
    return " ".join(title_lines), labels


def compare_sections(official_text, generated_text, language):
    """Return actionable gaps; official_text must be the matching language PDF."""
    errors = []
    extracted = []
    for label, text in (("official", official_text), ("generated", generated_text)):
        try:
            front, one, two, three = _parts(text)
            extracted.append((_paragraphs(front), _appendix1(one), _appendix2(two), _appendix3(three)))
        except ValueError as error:
            errors.append(f"{label} {language} section extraction: {error}")
    if errors:
        return errors
    source, generated = extracted
    for number in (1, 2, 3):
        try:
            source_heading = _heading(_parts(official_text)[number], number)
            generated_heading = _heading(_parts(generated_text)[number], number)
            errors.extend(_difference(f"appendix {number} title", source_heading[0], generated_heading[0]))
            errors.extend(_difference(f"appendix {number} column headings",
                                      " ".join(source_heading[1]), " ".join(generated_heading[1])))
        except ValueError as error:
            errors.append(f"{language} section extraction: {error}")
    for i, (wanted, actual) in enumerate(zip(source[0], generated[0]), 1):
        errors.extend(_difference(f"TSB paragraph {i}", wanted, actual))
    for i, name in enumerate(("countries", "network/ROA", "network codes", "origin indicators")):
        errors.extend(_difference(f"appendix 1 {name}", source[1][i], generated[1][i]))
    for network, wanted in source[1][4].items():
        if network in generated[1][4]:
            actual = generated[1][4][network]
            errors.extend(_difference(f"appendix 1 network {network} country", wanted["country"], actual["country"]))
            for field in ("network/ROA", "origin indicators"):
                errors.extend(_difference(f"appendix 1 network {network} {field}",
                                          " ".join(wanted[field]), " ".join(actual[field])))
    for i, name in enumerate(("network codes", "organizations")):
        errors.extend(_difference(f"appendix 2 {name}", source[2][i], generated[2][i]))
    for network, wanted in source[2][2].items():
        if network in generated[2][2]:
            errors.extend(_difference(f"appendix 2 network {network} organizations", wanted, generated[2][2][network]))
    for i, name in enumerate(("cessation list", "amendments form", "amendments heading")):
        errors.extend(_difference(f"appendix 3 {name}", source[3][i], generated[3][i]))
    return errors
