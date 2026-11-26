# frozen_string_literal: true

# Parent namespace for source-document readers.
#
# Source document readers parse the original ITU publication files
# (`.docx`, `.doc`, `.pdf`) into a common shape: a list of paragraphs and
# a list of tables. This lets verifiers compare ob-issues/ output against
# authoritative source content without each verifier knowing the file
# format.
#
# Readers are loaded lazily (autoload) so dependencies like +rubyzip+ or
# +nokogiri+ are only required if the corresponding reader is actually used.

module Ituob
  module SourceDocuments
    # document.rb also defines Table and Row; readers build those first.
    autoload :Document, 'ituob/source_documents/document'
    autoload :Table, 'ituob/source_documents/document'
    autoload :Row, 'ituob/source_documents/document'
    autoload :DocxReader, 'ituob/source_documents/docx_reader'
    autoload :DocReader, 'ituob/source_documents/doc_reader'
    autoload :LegacyDocConverter, 'ituob/source_documents/legacy_doc_converter'
    autoload :PdfReader, 'ituob/source_documents/pdf_reader'
  end
end
