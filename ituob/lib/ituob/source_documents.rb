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
    autoload :Document, 'ituob/source_documents/document'
    autoload :DocxReader, 'ituob/source_documents/docx_reader'
    autoload :DocReader, 'ituob/source_documents/doc_reader'
    autoload :PdfReader, 'ituob/source_documents/pdf_reader'
  end
end
