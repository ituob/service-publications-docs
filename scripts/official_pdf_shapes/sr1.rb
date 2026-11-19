# frozen_string_literal: true

require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # SR.1 service restrictions: one block per country, separated by blank
    # lines. A block opens with the country name in the three languages (one
    # line each, French, English, Spanish) and continues with its restriction
    # lines. Key = the first name line; text = the other two names and the
    # restriction lines joined, so wrapping does not matter. A blank-line chunk
    # that does not open with three name lines (a block split by a page break)
    # continues the previous block.
    class SR1 < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-SR.1-2012].freeze
      HEADER = %r{\A\s*(?:Country|Pays|País)/(?:geographical|zon[ae])}
      TITLE = /\A\s*[[:upper:]][[:upper:] ()\-,]{14,}\z/
      NAME_MAX = 70
      SENTENCE_END = /[.:;]\z/

      def rows(text)
        out = []
        body(text).each do |chunk|
          if names?(chunk)
            out << Row.new(chunk.first, chunk.drop(1).join(' '))
          elsif out.any?
            out.last.text = G4Text.squish("#{out.last.text} #{chunk.join(' ')}")
          end
        end
        out
      end

      # The preface ends at the first running head or table header after it.
      def prose_stop(lines, start)
        header = lines.each_index.find { |i| i > start && lines[i].match?(HEADER) }
        [super, header].compact.min
      end

      private

      # Chunks of squished lines after the first table header, furniture and
      # repeated page headings removed. A chunk that follows a page break is
      # tagged (see Chunk) so a block split by the break can be rejoined.
      def body(text)
        lines = G4Text.lines_of(text)
        start = lines.index { |l| l.match?(HEADER) }
        return [] unless start

        join_stubs(chunks_of(lines.drop(start + 1)))
      end

      Chunk = Struct.new(:lines, :after_break)

      def chunks_of(lines)
        chunks = []
        open_chunk = false
        broke = false
        lines.each do |l|
          if skip?(l)
            broke = true
            open_chunk = false
          elsif l.strip.empty?
            open_chunk = false
          else
            chunks << Chunk.new([], broke) unless open_chunk
            chunks.last.lines << G4Text.squish(l)
            open_chunk = true
            broke = false
          end
        end
        chunks
      end

      # A page break can split the three name lines of a block: the first one
      # or two sit at the foot of a page, the rest follow the next page head.
      # Such a stub is joined to the chunk after the break.
      def join_stubs(chunks)
        chunks.each_with_object([]) do |chunk, out|
          if out.last && chunk.after_break && stub?(out.last)
            out.last.lines.concat(chunk.lines)
          else
            out << Chunk.new(chunk.lines.dup, chunk.after_break)
          end
        end.map(&:lines)
      end

      def stub?(chunk)
        chunk.lines.size < 3 && chunk.lines.all? { |l| l.size <= NAME_MAX && !l.match?(SENTENCE_END) }
      end

      def skip?(line) = G4Text.furniture?(line) || line.match?(HEADER) || line.match?(TITLE)

      def names?(chunk)
        chunk.size >= 3 && chunk.first(3).all? { |l| l.size <= NAME_MAX && !l.match?(SENTENCE_END) } &&
          (chunk.size == 3 || chunk[3].size > 3)
      end
    end
  end
end
