# frozen_string_literal: true

# ITU Operational Bulletin tools.
#
# Top-level entry point for the +ituob+ gem. Sets up framework adapters and
# autoloads the public API. Each submodule's file (e.g. +ituob/models.rb+)
# declares the leaf autoloads for its own namespace.
#
# Domain vocabulary is documented in +CONTEXT.md+ at the repository root.

require 'lutaml/model'
require 'lutaml/model/xml/nokogiri_adapter'

Lutaml::Model::Config.configure do |config|
  config.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter
  config.yaml_adapter_type = :standard_yaml
  config.json_adapter_type = :standard_json
end

# Top-level namespace. Submodules are autoloaded on first reference.
module Ituob
  # Shared helpers used across model classes (text normalization, etc.).
  autoload :Helpers, 'ituob/helpers'

  # On-disk dataset directory abstraction (legacy validation API).
  autoload :Dataset, 'ituob/dataset'

  # Stateless utility modules (DeepFreeze, etc.).
  autoload :Support, 'ituob/support'

  # Canonical ITU Operational Bulletin date formatting (Roman-numeral month).
  autoload :ObDate, 'ituob/ob_date'

  # Per-dataset amendment/entry/action classes plus the OldIssue parser.
  autoload :Models, 'ituob/models'

  # Single-source-of-truth catalogs: publications, message types, action types.
  autoload :Catalogs, 'ituob/catalogs'

  # Domain value objects: IssueId, DatasetSlug, PublicationId, ChangeObject.
  autoload :Domain, 'ituob/domain'

  # Disk I/O abstractions: IssueRepository, DatasetRepository.
  autoload :Repositories, 'ituob/repositories'

  # Source content extractors: ProseMirrorExtractor, AdocTableExtractor.
  autoload :Extractors, 'ituob/extractors'

  # Idempotent cleanup passes following the Normalizer protocol.
  autoload :Normalizers, 'ituob/normalizers'

  # Invariant checks producing structured VerificationResults.
  autoload :Verifiers, 'ituob/verifiers'

  # Rendered-output comparisons (deployed vs new HTML).
  autoload :Auditors, 'ituob/auditors'

  # Register / patch / replay model.
  autoload :Registers, 'ituob/registers'

  # Readers for DOCX/DOC/PDF source documents.
  autoload :SourceDocuments, 'ituob/source_documents'

  # Report generation (YAML/HTML summaries).
  autoload :Reporting, 'ituob/reporting'

  # Per-type renderers (OCP registry: add new renderers by registering).
  autoload :Renderers, 'ituob/renderers'

  # Parity tooling: URL mapping for cross-site audits.
  autoload :Parity, 'ituob/parity'

  # CLI subcommands (Thor-based): dataset, schema, …
  autoload :Commands, 'ituob/commands'

  # Top-level CLI entry point.
  autoload :Cli, 'ituob/cli'
end
