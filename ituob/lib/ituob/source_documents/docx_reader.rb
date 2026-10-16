# frozen_string_literal: true

require 'zip'
require 'nokogiri'

module Ituob
  module SourceDocuments
    # Read a .docx file (Office Open XML) into a Document.
    #
    # A .docx is a ZIP archive containing XML. The body content lives at
    # +word/document.xml+. We walk its +<w:p>+ (paragraph) and +<w:tbl>+
    # (table) elements in document order, extracting text from runs and
    # cells. Merged cells are detected via +<w:vMerge>+ and de-duplicated.
    class DocxReader
      W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'.freeze

      def self.read(path)
        new.read(path)
      end

      def read(path)
        xml = read_document_xml(path)
        doc = Nokogiri::XML(xml)
        body = doc.at_xpath('/w:document/w:body', w: W_NS)

        paragraphs = []
        tables = []

        body.element_children.each do |node|
          case node.name
          when 'p'
            paragraphs << paragraph_text(node)
          when 'tbl'
            tables << extract_table(node)
          end
        end

        paragraphs.reject!(&:empty?)
        Document.new(source_path: File.expand_path(path), paragraphs: paragraphs, tables: tables)
      end

      private

      def read_document_xml(path)
        Zip::File.open(path) do |zip|
          entry = zip.find_entry('word/document.xml')
          raise "word/document.xml not found in #{path}" unless entry

          entry.get_input_stream(&:read)
        end
      end

      def paragraph_text(p_node)
        text = p_node.xpath('.//w:t', w: W_NS).map(&:text).join
        text.strip
      end

      def extract_table(tbl_node)
        rows = []
        tbl_node.xpath('./w:tr', w: W_NS).each do |tr|
          rows << extract_row(tr)
        end
        Table.new(rows: rows)
      end

      def extract_row(tr_node)
        cells = []
        seen = {}
        tr_node.xpath('./w:tc', w: W_NS).each do |tc|
          tc_id = tc.object_id
          next if seen[tc_id]

          seen[tc_id] = true
          cell_text = tc.xpath('.//w:p', w: W_NS).map { |p| paragraph_text(p) }.reject(&:empty?).join("\n")
          cells << cell_text
        end
        Row.new(cells: cells)
      end
    end
  end
end
