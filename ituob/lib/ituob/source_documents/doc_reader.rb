# frozen_string_literal: true

require 'open3'

module Ituob
  module SourceDocuments
    # Read a legacy .doc file (Word 97-2003) into a Document.
    #
    # Uses macOS +textutil+ to convert .doc to plain text on disk first,
    # then parses the text. (Cross-platform: a future adapter could use
    # +antiword+ or +libwpd+ instead. The Reader class is the seam.)
    class DocReader
      def self.read(path)
        new.read(path)
      end

      def read(path)
        text = convert_via_textutil(path)
        paragraphs = text.split(/\n\s*\n/).map(&:strip).reject(&:empty?)

        # .doc text conversion doesn't preserve table structure cleanly,
        # so we expose paragraphs only and leave tables empty.
        Document.new(source_path: File.expand_path(path), paragraphs: paragraphs, tables: [])
      end

      private

      def convert_via_textutil(path)
        Dir.mktmpdir('ituob-doc-') do |dir|
          out = File.join(dir, 'output.txt')
          stdout_str, status = Open3.capture2('textutil', '-convert', 'txt', '-output', out, path.to_s)
          raise "textutil failed: #{stdout_str}" unless status.success?

          File.read(out, encoding: 'utf-8')
        end
      end
    end
  end
end
