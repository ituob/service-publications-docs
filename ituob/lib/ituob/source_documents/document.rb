# frozen_string_literal: true

module Ituob
  module SourceDocuments
    # A parsed source document — its paragraphs and tables as plain Ruby.
    #
    # Format-agnostic: every reader (DocxReader, DocReader, PdfReader)
    # produces a Document. Verifiers consume Documents without knowing
    # the source format.
    Document = Struct.new(
      :source_path,    # String: absolute path to the source file
      :paragraphs,     # Array<String>: body paragraphs in order
      :tables,         # Array<Table>: body tables in order
      keyword_init: true,
    ) do
      # Total table row count across all tables.
      def total_table_rows
        tables.sum { |t| t.rows.length }
      end

      # Body text as a single newline-joined string.
      def body_text
        @body_text ||= paragraphs.join("\n")
      end

      # Single haystack of paragraphs + every table cell, for content lookup.
      def haystack
        @haystack ||= begin
          parts = paragraphs.dup
          tables.each do |t|
            t.rows.each do |r|
              r.cells.each { |c| parts << c }
            end
          end
          parts.join("\n")
        end
      end
    end

    # A table with rows of cells.
    Table = Struct.new(
      :rows, # Array<Row>
      keyword_init: true,
    )

    # A row of cells (each cell is a String).
    Row = Struct.new(
      :cells, # Array<String>
      keyword_init: true,
    )

    # Look up +needle+ (any case) in the haystack. Returns +true+ if found.
    def self.haystack_include?(document, needle)
      return false unless needle
      return false unless document.is_a?(Ituob::SourceDocuments::Document)

      document.haystack.include?(needle)
    end
  end
end
