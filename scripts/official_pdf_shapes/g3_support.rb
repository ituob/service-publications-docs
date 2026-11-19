# frozen_string_literal: true

module OfficialPdfComparison
  module Shapes
    # Line helpers shared by the shape files of the #89 G3 group (F.1, F.68,
    # F.400, M.1400, PP Res. 21). `pdftotext -layout` text in, plain values out.
    module G3Support
      PAGE_MARK = /[–-]\s*\d+\s*[–-]/
      DATE_FOOTER = /\A\s*\d+\.[IVX]+\.\d{4}/

      module_function

      # [[text, column], ...] for the cells of a line; a cell is a run of words
      # separated by single spaces, cells are separated by two or more.
      def cells_at(line)
        line.rstrip.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
      end

      def squish(str)
        str.gsub(/[‘’]/, "'").gsub(/[“”]/, '"').gsub(/[ \s]+/, ' ').strip
      end

      # The running footer of a page: "Annex to ITU OB ... - 3 -", with or
      # without the date, on either side.
      def furniture?(line)
        line.match?(PAGE_MARK) || line.match?(DATE_FOOTER) || line.match?(/\A\s*(?:Annex|Annexe|Anexo)\s+(?:to|au|al)\b.*\bOB\b/i) ||
          line.match?(/\A\s*(?:Service Publication|Publication De Service|Publicación de Servicio)\b/i)
      end

      def lines(text)
        text.lines.map { |l| l.delete("\f").rstrip }
      end

      # Words only, in sorted order. A table cell wraps differently in every
      # renderer (and pdftotext interleaves the cells of one row), so a row is
      # compared as the bag of its words, hyphens and punctuation dropped.
      def word_bag(str)
        squish(str).downcase.scan(/[[:alnum:]]+/).sort.join(' ')
      end
    end
  end
end
