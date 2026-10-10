# frozen_string_literal: true

# Parent namespace for verifiers.
#
# A verifier checks an invariant and produces a VerificationResult. They
# never modify data. Adding a new check = adding a new subclass — open
# for extension.

module Ituob
  module Verifiers
    autoload :Base, 'ituob/verifiers/base'
    autoload :ReferenceVerifier, 'ituob/verifiers/reference_verifier'
    autoload :PerIssueAuditor, 'ituob/verifiers/per_issue_auditor'
    autoload :SourceDocVerifier, 'ituob/verifiers/source_doc_verifier'
    autoload :LocalizationAuditor, 'ituob/verifiers/localization_auditor'
    autoload :DatasetSnapshotVerifier, 'ituob/verifiers/dataset_snapshot_verifier'
    autoload :CharExplodedDetector, 'ituob/verifiers/char_exploded_detector'
    autoload :ChangeSchemaVerifier, 'ituob/verifiers/change_schema_verifier'
    autoload :CatalogIntegrityVerifier, 'ituob/verifiers/catalog_integrity_verifier'
    autoload :SnapshotIntegrityVerifier, 'ituob/verifiers/snapshot_integrity_verifier'
    autoload :ParserEquivalence, 'ituob/verifiers/parser_equivalence'
  end
end
