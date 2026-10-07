= ITU OB Data Normalization — Domain Glossary

This document captures the domain language of the ITU Operational Bulletin
data normalization system. Code in `lib/ituob_tools/` uses these terms
verbatim for class, module, and variable names.

== Core entities

=== ITU Operational Bulletin (OB)

The premier cross-bureau ITU publication. Published every two weeks as a
numbered *Issue*. Each issue is a stitched collection of *Messages* of
varying *MessageTypes*.

=== Issue

A single edition of the OB, identified by an integer *IssueId* (e.g. 1163).
An issue has:

* `meta` — *IssueMetadata* (publication date, cutoff date, authors)
* `annexes` — snapshot of running annexes at publication time
* general messages — see *GeneralMessage*
* amendments — see *Amendment*

=== IssueId

An integer identifier for an OB Issue (range 669–1343 currently).

=== Message

A piece of information disseminated via an OB Issue. Maps to a section in
the issue. Has a *MessageType*.

=== MessageType

Classifies a Message. Two top-level categories:

* `General` — messages in the GENERAL INFORMATION section of an issue
* `Amendment` — messages in the AMENDMENTS TO SERVICE PUBLICATIONS section

General types subdivide into:

* `StructuredGeneralType` — `running_annexes`, `approved_recommendations`.
  These have predictable shapes (list of recommendations, list of annexes)
  and are emitted as `general/{type}.yaml`.
* `TextualGeneralType` — `sanc`, `iptn`, `ipns`, `mid`, `org_changes`,
  `misc_communications`, `service_restrictions`, `custom`,
  `callback_procedures`, `telephone_service`, `telephone_service_2`,
  `no_type`. These carry freeform ProseMirror doc content and are emitted
  as `{type}/NNN.yaml`.

=== Amendment

A message that modifies a *Publication* (a dataset or external list).
Always has an *AmendmentTarget* specifying the publication and (optionally)
the position being amended.

=== AmendmentTarget

A pair: { publication: *PublicationId*, position_on: date? }.

=== PublicationId

The string identifier used in source YAML to reference a published list or
dataset. Examples: `E118_IIN`, `M1400_ICC`, `NNP`, `R_SP_LM.V`,
`List of Coast Stations and Special Service Stations`.

=== DatasetSlug

The filesystem-safe form of a PublicationId, used as a directory name under
`ob-issues/{issue}/{slug}/` and `datasets/{slug}/`. Examples: `e118-iin`,
`m1400-icc`, `nnp`, `list-v`, `coast-stations`.

Each PublicationId maps to exactly one DatasetSlug. The mapping is defined
once in `ituob_tools.catalogs.publications`.

=== Dataset

A logical collection of data published as a list. Identified by a
DatasetSlug. Has a *DatasetMetadata* and a current snapshot of entries.
Lives under `datasets/{slug}/`.

=== Publication classification

A PublicationId is classified into exactly one of:

* `StructuredPublication` — its amendments have predictable per-entry shape
  and can be parsed into typed `ChangeObject`s. Examples: `E118_IIN`,
  `M1400_ICC`, `Q708_ISPC`.
* `TextualPublication` — its amendments are inherently freeform
  (prose + tables without per-entry structure). Emitted as `text.yaml`.
  Examples: `NNP`, `R_SP_LM.V`, `R_SP_LN.VIII`, `RR.25.1`, `BUREAUFAX`,
  `List of Coast Stations and Special Service Stations`, `E212_ICC`.

=== ChangeObject

A structured representation of a single change applied to a dataset. Has a
type (*ActionType*), an identifier (the record being changed), and the
data payload. Serialized as `ob-issues/{issue}/{slug}/NNN-{ACTION}.yaml`.

=== ActionType

One of `ADD`, `SUP`, `REP`, `LIR`, `MOD`, `DEL`. `LIR` (Lapsed/Inactive
Record) is treated as semantically equivalent to `REP` for carrier codes.

== Source data layers

=== itu-ob-data

The authoritative source-of-truth repository. Contains, per issue:

* `meta.yaml` — *IssueMetadata*
* `general.yaml` — general messages (one per MessageType)
* `amendments.yaml` — amendments (one per AmendmentTarget)
* `annexes.yaml` — running-annexes snapshot
* `amendments/{slug}.adoc` — optional AsciiDoc rendering of an amendment
  (used when the YAML content is empty or references the .adoc)

=== ProseMirror

A JSON-doc-tree format used in `general.yaml` and `amendments.yaml` for
freeform content. Nodes are dicts with `type` and `content`. Leaf text
nodes carry the actual strings. Table nodes have `table_row` → `table_cell`
children.

=== Service publications refs

Per-dataset `.doc`/`.docx` source documents in `service-publications-refs/`.
The authoritative source for dataset snapshots.

=== Per-issue OB Word docs

`T-SP-OB.{NNNN}-{YYYY}-OAS-MSW-E.docx` files in
`itu-ob-data/reference-docs/`. The authoritative source for issue body
content. Used for verification.

== Output layers

=== ob-issues/

Per-issue normalized output. See *Issue*.

=== datasets/

Per-dataset "today's data" output:

* `metadata.yaml` — *DatasetMetadata* (title, locale strings, source link)
* `schema-data.yaml` — JSON Schema for `data.yaml`
* `data.yaml` — current snapshot of the dataset
* `changes/` — optional per-change files (alternative to ob-issues/

== Pipeline concepts

=== Normalizer

A pass that transforms the data into a more canonical shape. Idempotent:
running twice produces the same output as running once. Examples:
`PhantomCleanup`, `FilenameCanonicalizer`, `ActionCoalesce`.

=== Verifier

A pass that checks an invariant without modifying data. Produces a
*VerificationResult* with structured findings. Examples:
`ReferenceVerifier`, `PerIssueAuditor`, `SourceDocVerifier`.

=== Extractor

A pass that reads source content (ProseMirror or .adoc) and emits
*ChangeObject*s. Examples: `ProseMirrorExtractor`, `AdocTableExtractor`.

=== Repository

An abstraction over disk I/O for a specific entity. Reads/writes YAML,
walks directory trees. Examples: `IssueRepository`, `DatasetRepository`,
`ChangeObjectRepository`.

== File-name conventions

Action files: `NNN-ACTION.yaml` where NNN is a zero-padded sequence number
(`001`, `002`, ...) and ACTION is one of `ADD`, `SUP`, `REP`, `LIR`,
`MOD`, `DEL`.

Text fallback: `text.yaml` — present when an amendment is textual or
when structured extraction failed and the source content is preserved
verbatim.

Placeholder: `placeholder.yaml` — present when an amendment is declared in
source with empty content (`contents: {}`). Acknowledges the declaration
without producing false data.

== ITU-specific abbreviations

* **ISPC** — International Signalling Point Code (Q.708)
* **SANC** — Signalling Area/Network Code (Q.708)
* **IIN** — Issuer Identification Number (E.118)
* **ICC** — ITU Carrier Code (M.1400)
* **MNC** — Mobile Network Code (E.212)
* **MCC** — Mobile Country Code (E.212)
* **DNIC** — Data Network Identification Code (X.121)
* **ADMD** — Administration Management Domain (F.400)
* **TDI** — Telegram Destination Indicator (F.32)
* **TNIC** — Telex Network Identification Code (F.68)
* **NNP** — National Numbering Plan (E.129)
* **MID** — Maritime Identification Digit
* **IPTN** — International Public Telecommunication Numbering Plan (E.164)
* **IPNS** — International Identification Plan for Public Networks and Subscriptions (E.212 shared MCC)
