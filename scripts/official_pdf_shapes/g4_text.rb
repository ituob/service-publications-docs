# frozen_string_literal: true

module OfficialPdfComparison
  module Shapes
    # Line helpers shared by the T.35, X.121 and SR.1 shapes.
    module G4Text
      # Running heads and page numbers in official and generated PDFs, all languages.
      FURNITURE = %r{
        \A\s*(?:Annex\s+to\s+ITU\s+OB|Annexe\s+au\s+BE|Anexo\s+al\s+BE)\b |
        \A\s*Service\s+Publication\s+Annex |
        \A\s*ITUPublications |
        \A\s*\d{1,2}\.[IVX]+\.\d{4}\s+[–-]\s*\d+\s*[–-] |
        \A\s*[–-]\s*\d+\s*[–-]\s*\z
      }x

      module_function

      def squish(str)
        str.gsub(/[‘’]/, "'").gsub(/[“”]/, '"').gsub(/[ \s]+/, ' ').strip
      end

      def lines_of(text)
        text.lines.map { |l| l.delete("\f").chomp }
      end

      def furniture?(line) = line.match?(FURNITURE)
    end

    # The preface of these publications is the "Note from TSB/BR" up to the first
    # running head after it (the table starts on the next page). The comparator
    # ends the prose at a "Country/geographical" header, which these tables do
    # not have, so the shape cuts the line list itself: it is the caller's own
    # array, and the comparator reads its size after this call.
    module G4Prose
      NOTE = /\A\s*(?:Note from (?:the )?[TB]SB?|Note du [TB]SB?|Nota de(?: la)? [TB]SB?)\b/

      # A PDF without the note has no preface: the empty range, so the other
      # PDF's preface shows as a delta.
      def prose_start(lines, _lang)
        start = lines.index { |l| l.match?(NOTE) } or return lines.size
        stop = lines.each_index.find { |i| i > start && G4Text.furniture?(lines[i]) }
        lines.slice!(stop..) if stop
        start
      end
    end
  end
end
