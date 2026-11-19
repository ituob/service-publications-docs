# Recheck of the 46 pinned replay conflicts

Rechecked against service-publications-docs main `8f19d30c` and the existing local
`itu-ob-data` corpus at
[`e17484be9f11d6a44d2f5c2ffc3d3e0813ffe62f`](https://github.com/ituob/itu-ob-data/tree/e17484be9f11d6a44d2f5c2ffc3d3e0813ffe62f). Each numbered row below corresponds to the original pinned
inventory, including each conflicting row of a multi-row amendment. The historical
issue description saying “10” conflicts understates that pinned inventory: it
contains 46 accumulated error events, not ten. The originating site snapshot is
[`e723b207f7266b23cf2731bae82f13ad0588dd48`](https://github.com/ituob/ituob.github.io/tree/e723b207f7266b23cf2731bae82f13ad0588dd48);
the service baseline is
[`8f19d30c`](https://github.com/ituob/service-publications-docs/tree/8f19d30c). **44 are
resolved on current main; 2 remain as documented source defects.** No source row,
canonical change, parser baseline, or replay conflict policy was changed for this
recheck. A parser cannot repair a wrongly targeted publication or invent an
allocation that the printed seed does not contain.

## Primary-source evidence

- **E118**: [OB 1161](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1161-2018-OAS-PDF-E.pdf),
  printed p. 13, Czech cancellation effective 6.XI.2018; same PDF's annex,
  printed pp. 19–20, contains the surviving Czech allocations and omits `89 420 06`.
  The annex is explicitly positioned at 1 December 2018. Corpus row:
  `itu-ob-data/issues/1161/amendments.yaml:573`.
- **F32-MY**: [OB 1013](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1013-2012-OAS-PDF-E.pdf),
  printed p. 12, Malaysia COL 1–5 SUP, date 1 July 2012: 17 offices from MAAS
  through MAMX. Their original allocations are in the checked-in
  `ituob/spec/fixtures/f32/official-2011.pdf` and extracted XML, printed Malaysia
  p. 27. `publication.yaml` supplies the complete seed; grouped withdrawal is
  expanded by `F32DirectoryChangeSource` against that seed. The old composite
  country/network/office-string key was not an allocation key.
- **F32-UA**: [OB 1148](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1148-2018-OAS-PDF-E.pdf),
  printed p. 13, Ukraine COL 1–5 SUP, cessation 1 March 2018. The first table
  row is a country/network heading, without an office allocation. The following
  office rows are printed on seed pp. 38–39. The source-complete publication
  retains the heading as context and keys allocations by four-letter indicator,
  so translated country labels cannot create different keys. Corpus rows begin
  at `itu-ob-data/issues/1148/amendments.yaml:1018` (UXCK).
- **Q708-DE/JP**: [OB 1109](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1109-2016-OAS-PDF-E.pdf),
  printed pp. 9–10, Germany SUP (six codes) and Japan SUP (three codes).
  The same PDF's annex is explicitly positioned at 1 October 2016 and omits
  these nine codes. `seed_includes_seed_issue` excludes these already embodied
  withdrawals, conditional on all targets being absent. Corpus references for
  all nine targets are given below; `seed_issue_replay_spec.rb` preserves the
  complete richer seed entries and empty seed-state errors.
- **M1400**: original `itu-ob-data/reference-docs/T-SP-OB.1167-2019-OAS-MSW-E.docx`:
  the Genza address, carrier code CH4141 and contact appear in the M.1400 table,
  before the Q.708 heading. The actual Q.708 amendment contains Spain LIR
  `2-238-0` and `2-238-2` (also transcribed in
  `itu-ob-data/issues/1167/amendments/q708-ispc.adoc`). In YAML, the valid M1400
  target begins at line 2629, Genza at 2879; a duplicate contact payload is
  wrongly tagged Q708_ISPC at line 2916, Genza at 3166. The canonical
  `datasets/1109-Q.708B/changes/1167-0002-SUP-Genza_SA_Rue_de_Lausanne_37_1201_GENEVE.yaml`
  consequently uses an address as `ipsc` and CH4141 as `dec`. This is an upstream
  publication-target error, not a missing signalling allocation. It remains
  observable; silently discarding it in the Q.708 parser would conceal the
  source error and would not repair the canonical change already on disk.
- **X121**: [OB 977 annex](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-X.121B-2011-PDF-E.pdf),
  printed p. 5: Belgium contains `206 2`, `206 4`, `206 5`, `206 6`, `206 7`,
  `206 8`, `206 9`, and no `206 1`. This agrees with the checked-in seed and supersedes the earlier
  `docs/normalization/replay-skips.adoc` statement that the original seed table
  was unavailable in repository text. The independent original PDF is available.
  [Original OB 1081](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1081-2015-OAS-PDF-E.pdf),
  printed p. 32 (also the general notice on p. 4), explicitly withdraws the six
  codes including 206 1. Its transcription is in
  `itu-ob-data/issues/1081/amendments.yaml:8735` and the row at 8845; it withdraws
  `206 1, 206 2, 206 4, 206 5, 206 8, 206 9`. No intervening canonical addition
  provides 206 1. Thus the printed history available here is incomplete or the
  later printed withdrawal includes an already absent code; it is not a seed
  extraction omission. The five held neighbors are withdrawn successfully.

## Per-row disposition

| Original row | Register / target | Current disposition and concrete evidence |
| --- | --- | --- |
| 1 | E118 / 89 420 06 | Resolved: post-amendment seed already omits cancelled code; **E118**. |
| 2 | F32 / Malaysia grouped offices | Resolved: all 17 printed office withdrawals apply against verified seed; **F32-MY**. |
| 3 | F32 / UKRAINE, UX- -, blank office | Resolved: country/network heading retained as context, not an allocation or removal target; **F32-UA**. |
| 4 | F32 / UXCK | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 5 | F32 / UXCG | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 6 | F32 / UXCV | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 7 | F32 / UXDP | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 8 | F32 / UXDC | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 9 | F32 / UXGR | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 10 | F32 / UXIF | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 11 | F32 / UXHR | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 12 | F32 / UXHS | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 13 | F32 / UXHM | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 14 | F32 / UXKG | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 15 | F32 / UXKM | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 16 | F32 / UXKR | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 17 | F32 / UXKV | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 18 | F32 / UXLK | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 19 | F32 / UXLC | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 20 | F32 / UXLV | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 21 | F32 / UXMR | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 22 | F32 / UXMK | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 23 | F32 / UXOD | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 24 | F32 / UXPL | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 25 | F32 / UXRV | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 26 | F32 / UXSV | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 27 | F32 / UXSF | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 28 | F32 / UXSU | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 29 | F32 / UXTR | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 30 | F32 / UXUG | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 31 | F32 / UXVC | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 32 | F32 / UXYL | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 33 | F32 / UXZP | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 34 | F32 / UXZT | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 35 | F32 / UXKX | Resolved: printed office is in verified seed and is withdrawn by indicator, independent of translated country label; **F32-UA**. |
| 36 | Q708 / 2-125-6 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 627. |
| 37 | Q708 / 2-248-4 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 669. |
| 38 | Q708 / 5-245-2 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 711. |
| 39 | Q708 / 5-245-6 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 753. |
| 40 | Q708 / 5-251-0 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 795. |
| 41 | Q708 / 6-237-4 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-DE**, corpus OB1109 line 837. |
| 42 | Q708 / 4-082-6 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-JP**, corpus OB1109 line 1189. |
| 43 | Q708 / 4-086-0 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-JP**, corpus OB1109 line 1231. |
| 44 | Q708 / 4-086-1 | Resolved: absent in post-amendment annex seed; same-issue SUP excluded. **Q708-JP**, corpus OB1109 line 1273. |
| 45 | Q708 / Genza address | Documented source defect: duplicated M.1400 contact table wrongly targeted Q708_ISPC; **M1400**. One current diagnostic retained. |
| 46 | X121 / 206 1 | Documented printed-history gap: absent in original OB977 Belgium table and intervening additions; later OB1081 nevertheless withdraws it; **X121**. One current diagnostic retained. |

## E.164 notes were seeded

The “Note N/O/PQ never seeded” statement is false on current main. All three
catalogue entries use seed issue 1114 and route changes from `e164-cc` by prefix
+881, +882 and +883 respectively. Seed data are present in
`datasets/1114-E.164D-Note-{N,O,PQ}/data.yaml`.

[Original OB 1114 E.164 annex](https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.164D-2016-PDF-E.pdf)
notes n/o/p/q prints these networks: note n groups Iridium's +881 6/7 and
Globalstar's +881 8/9; the seed expands those printed pairs into four entries.
The o, p and q tables print the +882 and +883 allocations.

| Register | Active entries at seed issue | Current active entries | Current replay errors |
| --- | ---: | ---: | ---: |
| E164_NOTE_N | 4 | 4 | 0 |
| E164_NOTE_O | 24 | 17 | 0 |
| E164_NOTE_PQ | 18 | 32 | 0 |

## Checks

Read-only current-state replays of the affected registers confirm
E118=0, F32=0, Q708=1 and X121=1 errors; the three E164 notes have zero errors.
A row-by-row replay check confirms every one of the 49 printed F.32 office
targets (17 Malaysian and 32 Ukrainian) is present immediately before its
withdrawal and absent immediately afterward. The heading in original row 3
adds no office target.

The broader existing replay-skip ledger contains four current events: the two
remaining pinned events plus E212 640 01 and 340 04, which were not in this
46-row inventory. Historical snapshots are not counted repeatedly.

Focused public regressions pass (6 examples, 0 failures) and cover the Malaysia and Ukraine withdrawals, the
independently applied X121 neighbors, complete Q708 seed preservation, and
Namibia's retained seed-issue date. Parser equivalence passes: `Result: EQUIVALENT` with `--verify`;
no `--capture`, full suite, build or PDF render is required by this recheck.

Executed from the repository root:

```sh
BUNDLE_GEMFILE=ituob/Gemfile bundle exec rspec --options /dev/null -I ituob/lib -I ituob/spec ituob/spec/ituob/registers/source_gap_replay_spec.rb ituob/spec/ituob/registers/seed_issue_replay_spec.rb
BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby -r liquid scripts/verify_parser_equivalence.rb --verify
```

`focused-quality`: report and existing replay/parser interaction; no code changes
or new actionable parser defect. The two remaining source defects above remain
visible diagnostics, with no corpus changes made by this recheck.
