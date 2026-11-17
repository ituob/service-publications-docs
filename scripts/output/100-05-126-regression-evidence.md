# Breaker regression evidence for #126

The breaker inspected `06a674ca`. Fresh `origin/main` (`1fc6e94a`) already includes
`d2d23324`, which corrected all seven findings before #126 merged. This follow-up
adds direct classifier assertions for every supplied synthetic reproduction,
including both unequal phone numbers, and records the exposed corpus lines.
No register data is changed.

## Per-finding behavior

1. Shared-code introductions match complete fixed table introductions only;
   issue 1252's VISIONng +878 10 deletion note remains unmapped.
2. Phone regrouping requires equal digit strings, preserving legitimate grouping
   changes while rejecting additional prefix or suffix digits.
3. Questionnaire exclusions require a complete known label; inline coordinates
   remain content. Mapping strips the label only when matching the answer.
4. Extra-territorial exclusions match fixed definitions and labels; assignment
   rows remain content.
5. Page headings strip only fixed directives; operator names and parenthesized
   carrier codes must map or remain unmapped.
6. Numeric footnotes require the complete known header shape; `Country code | 7`
   remains content and can map to a country-code patch.
7. Reference banners require bibliographic syntax; embedded ISPC assignments
   remain content.

## Verification

- Against `06a674ca`: eight classifier regressions fail with the reported wrong
  statuses (six excluded, two mapped-values-only).
- Current implementation: focused coverage and E.118 specs pass, 33 examples.
- Parser equivalence `--verify`: all 15 publications EQUIVALENT.
- Coverage report and both TSVs regenerated against current main patches; see totals below.
- `focused-quality`: complete follow-up diff and interaction with the existing
  seven corrections reviewed; no actionable findings.
- NOT RUN: full suite and local PDF rendering (requested limits); RuboCop is
  unavailable in `ituob/Gemfile`'s bundle (executable probe failed).

## Corpus totals

| State | Printed | Mapped | Excluded | Unmapped |
|---|---:|---:|---:|---:|
| Breaker's historical checked-in report (`06a674ca`) | 33,223 | 29,767 | 3,336 | 120 |
| Corrected checked-in report before regeneration | 33,223 | 29,846 | 3,216 | 161 |
| Old classifier (`06a674ca`), current patches | 33,223 | 29,766 | 3,342 | 115 |
| Corrected classifier, current patches (regenerated) | 33,223 | 29,845 | 3,223 | 155 |

The controlled comparison uses the same current patches and corpus (`e17484be`)
with both classifiers. It exposes 119 previously excluded lines: 79 now map and
40 remain unmapped; none of the old classifier's unmapped lines disappear.
The checked-in reports predate other merged patch changes on main, so comparing
historical totals alone also includes those unrelated changes. No data is edited.

## Newly unmapped printed lines

All 44 newly unmapped lines relative to the breaker's historical TSV are listed
conservatively, including headings with
unmatched tokens. These are coverage gaps for later data investigation; this
follow-up does not assert that every missing heading token needs a data change.
The VISIONng assignment-note deletion is a confirmed substantive omission.
Sources are within `itu-ob-data`; matching uses issue, register and exact text.
Forty arise in the controlled classifier comparison; four additional lines
(two headers and two assignment rows in issues 1094/1108) reflect changes to the
patch inputs since the breaker.

| Source | Register | Printed text |
|---|---|---|
| issues/957/amendments.yaml:4215 | e212-mnc | P  9  Georgia   LIR |
| issues/964/amendments.yaml:1863 | e118-iin | P  49     ADD     Vodafone Group Services Ltd, United Kingdom |
| issues/971/amendments.yaml:500 | m1400-icc | Liechtenstein (Principality of) / LIE Liechtenstein (Principauté de) / LIE Liechtenstein (Principalidad de) / LIE SUP \|   \|   |
| issues/971/amendments.yaml:786 | m1400-icc | Liechtenstein (Principality of) / LIE Liechtenstein (Principauté de) / LIE Liechtenstein (Principalidad de) / LIE ADD \|   \|   |
| issues/972/amendments.yaml:14 | e212-mnc | P   Sweden  ADD |
| issues/975/amendments.yaml:867 | e164-acn | P  9   Georgie   LIR * |
| issues/981/amendments.yaml:617 | e212-mnc | P  17    International Mobile, shared code          SUP 1 |
| issues/983/amendments.yaml:1657 | e212-mnc | P  17    International Mobile, shared codes        ADD 1) |
| issues/1009/amendments.yaml:837 | e212-mnc | P  40   Sweden   (extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212) |
| issues/1010/amendments.yaml:531 | m1400-icc | P  28  Allemagne Germany (Federal Republic of) / DEU    ADD \|   \|   \|   |
| issues/1015/amendments.yaml:658 | e212-mnc | P  7   Canada  (http://www.cnac.ca/other_codes/imsi/imsi_codes.htm) REP all information by |
| issues/1016/amendments.yaml:1935 | e212-mnc | P  16 to P  17    India     SUP |
| issues/1016/amendments.yaml:3047 | e212-mnc | P  16 to P  17   India      ADD |
| issues/1016/amendments.yaml:4919 | e212-mnc | P  40  Switzerland   ADD   (extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212) |
| issues/1022/amendments.yaml:388 | m1400-icc | P  28 Germany (Federal Republic of) / DEU     ADD |
| issues/1028/amendments.yaml:530 | m1400-icc | P  30   Gibraltar /GIB     SUP |
| issues/1028/amendments.yaml:666 | m1400-icc | P  49   Luxembourg/LUX     ADD |
| issues/1030/amendments.yaml:69 | e118-iin | P  United States     ADD |
| issues/1047/amendments.yaml:104 | e212-mnc | Sweden  SUP (extra-territorial use of MCC/MNC, Annex E to ITU-T Recommendation E.212) |
| issues/1086/amendments.yaml:522 | m1400-icc | Germany (Federal Republic of) / DEU     ADD  |
| issues/1094/amendments.yaml:1361 | e212-mnc | Country or Geographical Area \| MCC+MNC* \| MSIN** range to be used \| Operators Name |
| issues/1108/amendments.yaml:276 | e212-mnc | Country or Geographical Area \| MCC+MNC* \| MSIN** range to be used \| Operators Name |
| issues/1108/amendments.yaml:336 | e212-mnc | France (Country A) \| 208 10 \| 0000000000 - 2654099999; 2654200000 - 2654299999; 2654400000 - 2754099999; 2754200000 - 2754299999; 2754400000 - 9999999999 \| Société Française du Radiotéléphone |
| issues/1108/amendments.yaml:431 | e212-mnc | France (Country A) \| 208 20 \| 0000000000 - 0055499999; 0055600000 - 2007199999; 2007300000 - 9999999999 \| Bouygues Telecom |
| issues/1186/amendments.yaml:193 | e164-cc | country code      888      LIR |
| issues/1225/amendments.yaml:251 | e164-cc | country code      997       LIR |
| issues/1232/amendments.yaml:536 | e164-cc | country code      888       SUP |
| issues/1232/amendments.yaml:644 | e164-cc | SUP      notes k and t |
| issues/1232/amendments.yaml:666 | e164-cc | country code      888       LIR |
| issues/1252/amendments.yaml:310 | e164-cc | country code      970       LIR |
| issues/1252/amendments.yaml:408 | e164-cc | country code      878       SUP |
| issues/1252/amendments.yaml:514 | e164-cc | SUP      note e |
| issues/1252/amendments.yaml:522 | e164-cc | e            Associated with shared country code 878 for Universal personal telecommunications (UPT), the identification code 10 has been assigned to the network of VISIONng, +878 10. |
| issues/1252/amendments.yaml:532 | e164-cc | country code      878       LIR |
| issues/1264/amendments.yaml:350 | e212-mnc | International Mobile, shared code      ADD* \|   \|   |
| issues/1264/amendments.yaml:530 | m1400-icc |  Germany (Federal Republic of) / DEU                ADD |
| issues/1288/amendments.yaml:337 | m1400-icc |  Germany (Federal Republic of) / DEU                ADD |
| issues/1314/amendments.yaml:6911 | e118-iin | Global Issuer Identifier Number      LIR |
| issues/1314/amendments.yaml:7099 | e164-cc | country code      883       LIR |
| issues/1321/amendments.yaml:15 | e118-iin | Global Issuer Identifier Number      LIR |
| issues/1321/amendments.yaml:185 | e118-iin | Global Issuer Identifier Number      ADD |
| issues/1330/amendments.yaml:15 | e118-iin | Belarus (Rep of.)      ADD |
| issues/1341/amendments.yaml:15 | e164-cc | country code      997       LIR |
| issues/1349/amendments.yaml:409 | m1400-icc |  Germany (Federal Republic of) / DEU                LIR |
