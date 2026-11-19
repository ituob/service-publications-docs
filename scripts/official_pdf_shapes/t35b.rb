# frozen_string_literal: true

require_relative 'base'
require_relative 'g4_text'

module OfficialPdfComparison
  module Shapes
    # T.35 national authorities: one block per country, a heading line followed
    # by "Label: value" lines (administration, contact, address, ...). A row is
    # one block: key = country heading, text = the block's lines joined, so a
    # value that wraps differently reads the same.
    class T35B < Base
      include G4Prose

      PUBLICATIONS = %w[T-SP-T.35B-2012].freeze
      HEADING = /\A {0,3}[^\s:\d](?:[^:\d\s]| (?! )){0,58}\z/
      LABEL = /\A {0,3}\S[^:]{0,40}:(?: {2,}|\s*\z)/

      def rows(text)
        lines = G4Text.lines_of(text).map { |l| G4Text.furniture?(l) ? '' : l }
        out = []
        lines.each_with_index do |line, i|
          if heading?(lines, i)
            out << Row.new(G4Text.squish(line), '')
          elsif out.any? && !line.strip.empty?
            out.last.text = G4Text.squish("#{out.last.text} #{line}")
          end
        end
        out
      end

      private

      # A short colon-free line, after a blank line, whose next non-blank line is
      # a label line (starts a capital) or whose second one is a "Label:" line
      # (a label that wraps puts its colon on the second line).
      def heading?(lines, idx)
        return false unless lines[idx].match?(HEADING) && (idx.zero? || lines[idx - 1].strip.empty?)

        nxt = lines[(idx + 1)..].reject { |l| l.strip.empty? }.first(2)
        !nxt.empty? && nxt.first.match?(/\A {0,3}[[:upper:]]/) && nxt.any? { |l| l.match?(LABEL) }
      end
    end
  end
end
