= ITU OB Tools — Architecture

This document describes the architecture of the +ituob+ Ruby gem (in
+service-publications-docs/ituob/+), which provides the data
normalization, verification, and reporting pipeline for the ITU
Operational Bulletin system.

Domain vocabulary is documented in link:../CONTEXT.md[CONTEXT.md]. This
file uses those terms verbatim.

== Model ontology (LML)

All model data shapes are declared once in
`lib/ituob/ontology/messages.lml` (LutaML Model Language). The
ontology is validated by the RS 3001 rules, compiled by
`Lutaml::Lml::ModelCompiler`, and enforced against the Ruby classes by
`spec/ituob/ontology_spec.rb` — a failing spec means the ontology and
the classes have drifted apart.

Pure data-shape classes are compiled from the ontology at load time
(`lib/ituob/models/compiled.rb`, currently the List VIII family);
classes whose behavior dominates (the per-publication parsers) remain
hand-written and are kept in lockstep by the drift guard instead.

== Layering

The package is organized in MECE layers. Each layer depends only on the
layers beneath it:

[cols="1,4,1"]
|===
| Layer | Responsibility | Examples

| Catalogs
| Single-source-of-truth lookup tables
| `Catalogs::Publications`, `Catalogs::MessageTypes`, `Catalogs::ActionTypes`

| Domain
| Immutable value objects representing domain concepts
| `Domain::IssueId`, `Domain::ChangeObject`, `Domain::Amendment`

| Repositories
| Disk I/O (read/write YAML, walk directory trees)
| `Repositories::IssueRepository`, `Repositories::DatasetRepository`

| SourceDocuments
| Read source files (DOCX/DOC/PDF) into a common Document shape
| `SourceDocuments::DocxReader`, `SourceDocuments::DocReader`, `SourceDocuments::PdfReader`

| Extractors
| Convert source content into `Domain::ChangeObject` instances
| `Extractors::AmendmentExtractor`, `Extractors::ProseMirror`

| Normalizers
| Idempotent cleanup passes that canonicalize the output
| `Normalizers::PhantomCleanup`, `Normalizers::FilenameCanonicalizer`

| Verifiers
| Invariant checks that produce structured `VerificationResult`s
| `Verifiers::PerIssueAuditor`, `Verifiers::ReferenceVerifier`

| Reporting
| Render verification results as YAML, HTML, or stdout summaries
| `Reporting::Report`
|===

== Module organization

Every submodule has a parent-namespace file that declares its leaf
autoloads. Per project rule, NO `require_relative` is used inside the
library — only `autoload`.

[source]
----
ituob/lib/
├── ituob.rb                      # top-level: loads framework + autoloads submodules
├── ituob/
│   ├── models.rb                 # autoloads every Ituob::Models:: leaf
│   ├── catalogs.rb               # autoloads catalogs/* leaves
│   ├── domain.rb                 # autoloads domain/* leaves
│   ├── repositories.rb           # autoloads repositories/* leaves
│   ├── extractors.rb             # autoloads extractors/* leaves
│   ├── normalizers.rb            # autoloads normalizers/* leaves
│   ├── verifiers.rb              # autoloads verifiers/* leaves
│   ├── source_documents.rb       # autoloads source_documents/* leaves
│   ├── reporting.rb              # autoloads reporting/* leaves
│   ├── catalogs/
│   │   ├── action_types.rb       # Catalogs::ActionTypes
│   │   ├── message_types.rb      # Catalogs::MessageTypes
│   │   └── publications.rb       # Catalogs::Publications
│   ├── domain/
│   │   ├── identifiers.rb        # IssueId, DatasetSlug, PublicationId, RecordCode
│   │   ├── change_object.rb      # ChangeObject value
│   │   ├── amendment.rb          # Amendment value
│   │   └── issue.rb              # Issue value
│   ├── repositories/
│   │   ├── yaml_store.rb         # low-level read/write
│   │   ├── issue_repository.rb   # OB Issue read/write
│   │   ├── dataset_repository.rb # dataset read
│   │   └── change_object_repository.rb
│   ├── extractors/
│   │   ├── base.rb               # Extractor interface
│   │   ├── prosemirror_walker.rb # shared tree-walking utilities
│   │   ├── prosemirror.rb        # generic ProseMirror extractor
│   │   ├── amendment_extractor.rb # picks extractor per publication
│   │   └── general_message_extractor.rb
│   ├── normalizers/
│   │   ├── base.rb               # Normalizer interface + Result struct
│   │   ├── pipeline.rb           # orchestrator (fixed idempotent order)
│   │   ├── phantom_cleanup.rb
│   │   ├── action_splitter.rb
│   │   ├── action_merger.rb
│   │   ├── filename_canonicalizer.rb
│   │   ├── orphan_phantom_to_fallback.rb
│   │   ├── empty_dir_filler.rb
│   │   └── empty_amendment_placeholder.rb
│   ├── verifiers/
│   │   ├── base.rb               # Verifier interface + Result struct
│   │   ├── reference_verifier.rb
│   │   ├── per_issue_auditor.rb
│   │   ├── source_doc_verifier.rb
│   │   ├── localization_auditor.rb
│   │   ├── dataset_snapshot_verifier.rb
│   │   └── char_exploded_detector.rb
│   ├── source_documents/
│   │   ├── document.rb           # Document/Row/Table value structs
│   │   ├── docx_reader.rb        # uses rubyzip + nokogiri
│   │   ├── doc_reader.rb         # uses macOS textutil
│   │   └── pdf_reader.rb         # uses Z.AI GLM-OCR
│   ├── reporting/
│   │   └── report.rb
│   └── models/                   # (existing) per-dataset amendment classes
└── ...
----

== Open/Closed extension points

Adding a new capability means ADDING a file, not modifying existing code:

=== New dataset / publication

. Add an entry to `Catalogs::Publications::REGISTRY` (one line).
. Done. Every other module sees the new publication through the catalog.

=== New general message type

. Add the type name to the appropriate set in `Catalogs::MessageTypes`
  (`STRUCTURED` or `TEXTUAL`).
. Done.

=== New action type

. Add the keyword to `Catalogs::ActionTypes::ALL`.
. Done.

=== New normalizer (cleanup pass)

. Subclass `Normalizers::Base`.
. Implement `#apply_to(issue_id)`.
. Optionally register it in `Normalizers::Pipeline::DEFAULT_STEPS`.

=== New verifier

. Subclass `Verifiers::Base`.
. Implement `#verify` (returning a `Verifiers::Base::Result`).

=== New source document format

. Add a reader class in `SourceDocuments/` that produces a
  `SourceDocuments::Document`.
. Verifiers consume `Document` without knowing the source format.

== Testing

Specs live in `ituob/spec/`. The convention is one spec file per class
under `spec/ituob/<submodule>/<class_name>_spec.rb`.

Per project rules:

* NO `double`s. Use real model instances.
* Integration specs use real fixtures from `itu-ob-data/issues/`.
* Unit specs use small inline fixtures or fakes.

Run with: `bundle exec rspec`

== Performance

The architecture supports lazy loading (autoload). Only the leaves you
reference are loaded. This keeps startup fast and avoids circular
dependency issues.

For batch operations across all 389 issues, use the iterator pattern
(`each_source_issue_id`, `each_dataset_slug`) — never load everything
into memory at once.

== Idempotency

Every normalizer is idempotent: running it twice produces the same output
as running once. The `Pipeline` enforces a fixed order so the composition
is also idempotent.

Verifiers never modify data; running them any number of times has no
side effects.

== Avoid: anti-patterns

* ❌ `require_relative` inside library code — use `autoload`.
* ❌ Hand-rolled serialization — `Repositories::YamlStore` is the single
  place for YAML I/O.
* ❌ Duplicating constants — everything lives in `Catalogs` once.
* ❌ `double` in specs — use real instances.
* ❌ Storing the same fact in two places — `PublicationId#slug` resolves
  through `Catalogs::Publications`, never duplicated on the instance.
