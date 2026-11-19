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

      private

      # Chunks of squished lines after the first table header, furniture and
      # repeated page headings removed.
      def body(text)
        lines = G4Text.lines_of(text)
        start = lines.index { |l| l.match?(HEADER) }
        return [] unless start

        cleaned = lines.drop(start + 1).map { |l| skip?(l) ? '' : G4Text.squish(l) }
        cleaned.slice_when { |a, b| a.empty? != b.empty? }.reject { |c| c.first.empty? }
      end

      def skip?(line) = G4Text.furniture?(line) || line.match?(HEADER) || line.match?(TITLE)

      def names?(chunk)
        chunk.size >= 3 && chunk.first(3).all? { |l| l.size <= NAME_MAX && !l.match?(SENTENCE_END) } &&
          (chunk.size == 3 || chunk[3].size > 3)
      end
    end
  end
end
