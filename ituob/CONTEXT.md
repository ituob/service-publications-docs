# ITUOB Gem — Architecture Context

## Domain vocabulary

- **Recommendation** — An ITU-T Recommendation document (E.212, E.164,
  M.1400, F.1, etc.) that creates one or more Registers.
- **Register** — A named dataset mandated by a Recommendation. The
  register's state evolves over time through OB patches. Example:
  `E212_MNC` (Mobile Network Codes) is created by Recommendation E.212.
- **Service Publication (SP)** — A printable document rendering the
  register at a point in time (e.g., `T-SP-F.1-1998-MSW-E.doc`).
- **OB Issue** — A numbered ITU Operational Bulletin. Contains messages
  (patches) that modify registers.
- **Change** — A single patch against a register. Identified by an OB
  action type: ADD, SUP, REP, LIR, MOD, DEL, or SEED.
- **State** — The replayed content of a register at a point in time.
  Produced by applying all changes with `ob_issue_no <= N` in order.
- **StateDiff** — Structured diff between two States at different OB
  issues. See `Registers::StateDiff` (TODO 41).
- **Seed** — The initial publication of a register, treated as a batch
  of ADD patches at the seed OB issue.

## Subsystems

### Catalogs (`Ituob::Catalogs`)
- `YamlCatalog` — mixin for lazy-loaded YAML catalogs. Hosts provide
  `yaml_key`, `primary_key`, `default_path`, `build_entry`, and
  optionally `declare_indices` for secondary lookups (TODO 37).
- `Registers` — includes `YamlCatalog`. Loads
  `catalogs/registers.yaml`. Single source of truth for register
  identity (ID, slug, recommendation, key_field, seed).
- `Recommendations` — includes `YamlCatalog`. Loads
  `catalogs/recommendations.yaml`.
- `Publications` — deprecated shim delegating to `Registers`.
- `MessageTypes`, `ActionTypes` — OB message and action type catalogs.

### Registers (`Ituob::Registers`)
- **Value objects**: `ActionType`, `Identifier`, `Change`, `State`,
  `StateDiff`. All frozen on construction. Comparable where it makes
  sense.
- **State** — immutable replayed state. Carries `entries`,
  `lapsed_keys`, `deleted_keys`, `history`, `error_count`, `errors`
  (preserved messages, TODO 60), `lapse_reasons` (TODO 61).
- **StateBuilder** — mutable working state used by Replay. Strategies
  mutate it; `#to_state(N)` freezes into a `State`.
- **StateDiff** — value object produced by `Replay#diff(from, to)`.
  Reports added/removed/modified/lapsed/unlapsed keys (TODO 41).
- **Change sources**: `ChangeSource` (abstract), `DirectoryChangeSource`
  (filesystem-backed), `InlineChangeSource` (in-memory, TODO 42).
- **Replay** — pure functional service. `at_issue(N)` returns a frozen
  `State`. `build_all_states` captures all point-in-time states in one
  O(N) pass. `diff(from, to)` returns a `StateDiff`.
- **SnapshotWriter** — writes a register's full set of point-in-time
  snapshots to disk (TODO 44). Encapsulates mkdir + JSON.pretty_generate
  calls.
- **Strategies**: `Strategies::{Add,Sup,Rep,Lir,Mod,Del,Seed}` — one
  class per action type. `Resolver` dispatches by convention (TODO 39):
  action value ADD → `Strategies::Add`. Each strategy declares
  `destructive?` (TODO 50); `ActionType#destructive?` delegates.
  `ActionType` predicates are auto-generated from `VALID_TYPES`
  (TODO 46).

### Support (`Ituob::Support`)
- `DeepFreeze` — recursive freeze for Hash/Array/leaves (TODO 38).
- `HashField` — string/symbol key lookup with string-wins-over-symbol
  precedence + canonical string-form set (TODO 47). Used by Identifier
  and per-action strategies.
- `Yaml` — centralized `safe_load_file` / `safe_load_string` with the
  project's standard policy (TODO 49).

### Parity (`Ituob::Parity`)
- `UrlMap` — URL mapping from deployed Jekyll permalinks to Astro
  URLs (TODO 53, 59). Used by `scripts/audit_link_parity.rb` and its
  spec.

### Verifiers (`Ituob::Verifiers`)
- `ChangeSchemaVerifier` — validates change files against
  `schema-change.yaml`.
- `CatalogIntegrityVerifier` — cross-checks catalogs against seed
  data on disk.
- `SnapshotIntegrityVerifier` — cross-checks generated snapshots
  against the catalog (TODO 40). Wired into `generate_register_snapshots.rb`.
- `PerIssueAuditor`, `ReferenceVerifier` — existing OB-data checks.

### Auditors (`Ituob::Auditors`)
- `ContentParity` — pure comparator for HTML rendering parity. Used
  by both `audit_content_parity_full.rb` (issue pages) and
  `audit_content_parity_all_pages.rb` (all page types).

### Existing subsystems (pre-register model)
- `Models` — per-register amendment parsers (E118Amendment, etc.).
- `Extractors` — ProseMirror walker for source content.
- `Normalizers` — idempotent pipeline (filename cleanup, phantom
  removal, action splitting/merging).
- `Repositories` — IssueRepository, DatasetRepository, ChangeObject.
- `SourceDocuments` — DOCX/DOC/PDF readers.

## Data flow

```
ITU OB bulletin PDFs
  → extracted to ProseMirror YAML in messages/ (source)
  → parsed by Models::*Amendment into actions/ (structured)
  → migrated to schema-change.yaml in changes/ (patches)
  → replayed by Registers::Replay into State (point-in-time)
  → serialized via State#to_snapshot + SnapshotWriter to JSON files
  → rendered by Astro into HTML pages
  → audited by Auditors::ContentParity + Parity::UrlMap against
    the deployed Jekyll reference
```

## Key conventions

- Ruby autoload only — no `require_relative` in lib/.
- All value objects frozen on construction.
- Strategies are stateless class methods (no instances).
- JSON Schema for data validation; Ruby strategies for semantic
  enforcement.
- `registers.yaml` and `recommendations.yaml` are the single source of
  truth. Adding a register = appending one entry. No code changes.
- New action types require only: append to `ActionType::VALID_TYPES`
  and create `Strategies::Foo < Base` with optional `destructive?`
  override.
- New YAML catalogs require only: a module that includes `YamlCatalog`
  with `yaml_key`, `primary_key`, `default_path`, `build_entry`.
- Parity audits run against `.parity-reference/jekyll/_site/`
  (persistent reference, git-ignored). See
  `service-publications-docs/scripts/parity_report.rb`.

## TODO cross-references

The architecture above was built up across TODOs in
`TODO.consolidate-schemas/`. Notable entries:

- 37 — YamlCatalog mixin
- 38 — DeepFreeze utility
- 39 — Convention-based strategy resolution
- 40 — SnapshotIntegrityVerifier
- 41 — Replay#diff API
- 42 — InlineChangeSource
- 43 — StateBuilder deep-freeze correctness
- 44 — SnapshotWriter + State#to_snapshot
- 46 — ActionType predicate auto-generation
- 47 — Support::HashField
- 49 — Support::Yaml
- 50 — Strategy declares destructive?
- 52 — Recommendation per-year archive
- 53 — Link parity auditor fixes
- 56 — Page-by-page validation report
- 59 — Specs for parity tooling
- 60 — Preserve error messages in State
- 61 — Preserve lapse_reasons in State
