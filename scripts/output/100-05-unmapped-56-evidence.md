# Unmapped 56 resolution — card 100-05

Base: `8f19d30c` (origin/main). Printed source: itu-ob-data `e17484be`.
All 56 input rows were checked; the companion
[resolution TSV](100-05-unmapped-56-resolution.tsv) records each row's final
classification and matching patch. The regenerated coverage report and TSVs use
33,223 printed lines from the same source and extraction method as the base.

## Patterns

| Pattern | Result and actual cause | Regression evidence |
|---|---|---|
| A | Fixed country/ISO loss. Existing slash/action normalization already handles the reported spellings, but the paragraph guard inspected only the first text node. A standalone `P` or short whitespace node skipped a complete heading. Check the full joined paragraph instead. Country/ISO context and printed actions now survive; 1028 SUP and 1349 LIR also replace their default ADD envelopes. | Three actual-source cases fail before and pass after; three checked-in output cases also fail before regeneration and pass afterward. Paragraph/table, translated-heading and annotation controls remain green. |
| B | Whole-label matching prevents `Tel` in Bantel/Eitel/Bartel, TeleData and email domains from becoming a phone. Recognize E-mai:l and Email/E-mail; stop at a different inline label, retaining repeated same-label phone values. | Surname, malformed-email-label, `.tel` domain and repeated-Tel controls fail with the old helper and pass with the correction. |
| C | Keep all address paragraphs, joining overflow into the existing address_line_3 convention. Eight entries improve: 1147, 1209, 1221 ×3, 1240, 1262, 1314. | Four/five-line and real-source cases fail before and pass after. Onvoy keeps addressee, street and locality; Coolwave's Ireland is restored. David Williams was already present. |
| D | Confirmed before changing: 1018, 1027 and 1039 all contain ignored code_block contact nodes; 1018 mixes these with paragraphs. Read their text lines alongside existing paragraph/table nodes. | Actual-source tests restore contact, address, phone, fax and email while preserving the other columns. |
| E | Split semicolon/inline multiple numbers and append unlabelled international-number continuation lines. | All five source cases fail before and pass after, including three Colombian numbers and both UK/USA numbers. Existing wrapped-number/email controls remain green. |
| F | Recognize a no-colon Fax label when followed by a number. | All three source rows fail before and pass after. |
| G | Confirmed a register field, but these are **Part III page references**, not frequency designators. The trilingual Part III/Page header and seventh source cell contain `166 f 175 e 184 s`; the parser incorrectly read the sixth cell. Populate existing part_iii_reference and preserve the split Part II section/page cells. | 974/991 source tests fail before and pass after; contacts, address and other fields remain identical. |
| H | Extract both Dito contact names and labelled values around the nested-table em dashes; split its two emails. | Dito/name/email controls fail before and pass after. |
| I | Use existing amendment notes, serialized into every issue action's data.notes. Capture starred paragraph/table notes alongside the glossary. Remove footnotes previously emitted as fake entries/actions. | 982/1330 fail before and pass after; glossary and real-entry preservation assertions cover neighboring cases. |

No schema or dependency changes. List VIII is an external catalog register without
a seed_path, so it has no derived dataset change directory to regenerate.

## Erratum and other rows

| Issue/register | Finding and treatment |
|---|---|
| 975/e164-acn | Printed `Georgie` conflicts with the structured `Georgia`; retain the correct country and explicitly leave this typo unmapped. |
| 989/e212-mnc | `Corrigendum1)` is a standalone marker, not missing correction content. A narrowly anchored exclusion handles only that marker. The dated footnote and correction text still require mapping; negative controls preserve them. |
| 996/t35-na; 1000/t35-na ×2 | Exact full phone equality already succeeded, but removing the phone tokens left an empty set that the matcher rejected. Accept that case only when a complete stored phone matched. Missing/different numbers and bare labels are tested. |
| 1001/e164-acn | The original classification was incorrect: this was actual data loss, not case folding. The extractor took only the first inline text node. Read the complete cell, retaining all five Brazil number patterns. |
| 1023/e118-iin; 1028/e118-iin | `366 St` and `r.l 4` were mistaken for detached superscripts (`366st`, `l4`). Try literal token spelling as an alternative; every original word/digit still has to match. Missing-company controls remain unmapped. |
| 1048/e118-iin | Content exists as `n0 28,60`; the coverage table flattener inserts spaces around marked superscript zeroes (`n 0 28,6 0`). Left unmapped. Blindly joining numeric tokens would weaken the number-preservation checks; a source-mark-aware extraction change is a separate matcher change. No parser/data correction needed. |
| 1167/q708-ispc | Source register attribution is wrong; all carrier/contact values are in the same issue's m1400 patch. Apply label stripping and exact number matching to other-register structured patches too, retaining the mapped_other classification. |
| 1334/e118-iin | Actual data loss: broad Mobile-label matching consumed `Mobile Business Strategy Department`, the division and `19F` address. Require punctuation or a numeric phone value for Mobile. Malformed Tel +: remains preserved. |

## Recount

| Register | Before | After |
|---|---:|---:|
| e118-iin | 22 | 8 |
| e164-acn | 3 | 1 |
| e212-mnc | 2 | 1 |
| list-viii | 2 | 0 |
| m1400-icc | 22 | 5 |
| q708-ispc | 2 | 0 |
| t35-na | 3 | 0 |
| **Total** | **56** | **15** |

Every one of the 32 originally classified real-content rows now maps. Eight of
nine other rows map; one marker is excluded. The 15 residuals are the original
13 layout/heading rows, the Georgie typo, and the 1048 spacing mismatch. No new
unmapped row was introduced. Mapped lines increase 29,936 → 29,980; exclusions
3,231 → 3,228 (four List VIII headings now map through their restored references,
plus the one Corrigendum marker).

## Regeneration and print checks

Generated the five affected publications through the existing build_ob_issues
emitter into disposable output. Integrated the emitted fields into affected
issue actions, preserving unrelated authored envelopes/corrections. Only the
seven heading envelopes whose parser metadata changes in A receive that metadata.
Regenerated derived changes for M1400_ICC, E118_IIN, E164_ACN and Q708_ISPC; retained
only affected amendment actions so existing unrelated derived drift is excluded.
Recaptured only the five changed parser baselines; the other ten are unchanged.

Every changed M1400 issue entry was compared with the English printed source:
301 entries / 590 changed values or removals, no mismatches. Entry counts/order
are preserved; allowed fields are country/ISO, contact, tel/fax/email and address
overflow. All 62 removed bogus tel strings are email/name substring matches.
Seven A envelope changes are accounted for above. The repeated 1086 telephone
pair remains intact. Existing normalized filename/type quirks outside A remain.

E118 comparison covers 269 source amendments / 908 entries: 19 entries change in
16 issues, only contact/address/tel/fax/email; other fields and entry counts are
preserved. All changed contacts/numbers were checked against the source cells.

The other 11 changed baseline records are explained completely: E164 adds three
date notes, removes three fake date actions and their seven duplicate entry
copies, restores three Brazil values and normalizes whitespace in two country
and two mobile values. Q708 moves two fake note entries into notes and restores
1330's paragraph note, preserving all real entries and glossary order. List VIII
adds just the two Part III references. Existing E164 repetition of tables under
real actions is unchanged.

All 172 affected derived paths were checked against source values: 649 changed
string values, with only two `_class: M1400Amendment` metadata strings requiring
non-print interpretation. Both are the normal envelope marker emitted when the
payload contains multiple entries; all content values match the source. Derived
payloads follow the existing migration shape, including its single-entry form.

## Verification and correctness review

All Ruby commands use `BUNDLE_GEMFILE=ituob/Gemfile bundle exec`.
Focused integrated RSpec: **237 examples, 0 failures**, using `--options /dev/null
-Iituob/spec --require spec_helper` and only the changed helpers/models/source,
generated-heading, Q708-neighbor and coverage spec files. The root .rspec has a
broad pattern: early accidental broad selections were stopped; no full-suite
completion is claimed. New behavioral regressions were observed red against the
old implementation before the green runs. The coverage tests also retain prefix/
suffix phone mismatches, missing assignments and non-layout content.

`ruby scripts/verify_parser_equivalence.rb --verify`: **EQUIVALENT**, all 15
publications, against the reviewed and refreshed baselines. Stable coverage and
all 56 row resolutions were regenerated after the final data changes. Ruby syntax
and `git diff --check` pass.

focused-quality: final correctness review of the complete implementation and
its generated-data interactions; the `.tel` boundary and repeated-Tel preservation
findings were corrected and verified. No remaining in-scope correctness finding.

NOT RUN: full local suite completion, local site build, PDF rendering, and
RuboCop (not present in ituob/Gemfile's bundle). CI is delegated to the owner's
script: confirm its run starts after push and exit without waiting.
