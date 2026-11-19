# frozen_string_literal: true

# Text helpers shared by the E.118, E.164 and E.180 table shapes. They work on
# `pdftotext -layout` output and keep to what the shapes need: page furniture
# removal, cell splitting and column-wise row text.
module OfficialPdfComparison
  module Shapes
    module G1Support
      BIDI = /[‎‏‪-‮⁦-⁩]/
      # A body line and the page it is printed on. Later pages of the generated
      # PDFs shift the table sideways, so a wrap line is read against the columns
      # of the first row of its own page (see column_text).
      Line = Struct.new(:text, :page)
      Cell = Struct.new(:text, :start) do
        def center = start + (text.size / 2.0)
      end

      module_function

      def squish(str) = str.gsub(BIDI, '').gsub(/[[:space:]]+/, ' ').strip

      def cells(line)
        line.gsub(BIDI, '').rstrip.to_enum(:scan, /\S+(?: \S+)*/).map { Cell.new(Regexp.last_match[0], Regexp.last_match.begin(0)) }
      end

      # Lines of the document (NFKC normalised: the generated Arabic text uses
      # presentation forms, the official one plain letters) without page furniture: the last non-blank line of
      # every page (the footer) and the lines that open at least `share` of the
      # pages (the repeated table header). Both PDFs print them differently, and
      # a footer or header is never row text.
      def body_lines(text, share: 0.35)
        pages = text.split("\f").map { |p| p.lines.map { |l| l.chomp.gsub(BIDI, '').unicode_normalize(:nfkc) } }
        heads = Hash.new(0)
        pages.each { |p| p.reject { |l| l.strip.empty? }.first(5).map { |l| squish(l) }.uniq.each { |l| heads[l] += 1 } }
        header = heads.select { |_, n| n >= 2 && n >= share * pages.size }.keys
        pages.each_with_index.flat_map do |lines, n|
          last = lines.rindex { |l| !l.strip.empty? }
          lines.each_with_index.filter_map { |l, i| Line.new(l, n) unless i == last || header.include?(squish(l)) }
        end
      end

      # Text of one row: the first line's cells are the columns; every later
      # cell is assigned to the column its start (:start) or centre (:center) is
      # nearest to. Reading order is kept inside a column, so a name wrapped
      # differently in the two PDFs still gives the same column text. heads maps
      # a page to the cells of its first row line; a wrap line on another page
      # than the row's first line is read against that page's columns.
      def column_text(lines, heads, align: :start, &split)
        split ||= :itself.to_proc
        first = lines.first
        head = split.call(cells(first.text))
        cols = head.map { |c| [c.text] }
        lines.drop(1).each do |line|
          ref = line.page == first.page ? head : (heads[line.page] || head)
          split.call(cells(line.text)).each { |c| cols[[nearest(ref, c, align), cols.size - 1].min] << c.text }
        end
        cols.map { |col| squish(col.join(' ')) }.join(' | ')
      end

      # page => cells of the first row-start line printed on it
      def page_heads(starts, &split)
        split ||= :itself.to_proc
        starts.each_with_object({}) { |line, h| h[line.page] ||= split.call(cells(line.text)) }
      end

      def nearest(head, cell, align)
        if align == :start
          head.rindex { |h| h.start <= cell.start + 2 } || 0
        elsif align == :overlap
          # the column whose first-line text the cell starts under, else the
          # column with the nearest centre (right and centre aligned cells)
          head.rindex { |h| cell.start.between?(h.start - 3, h.start + h.text.size + 1) } ||
            head.each_index.min_by { |i| (head[i].center - cell.center).abs }
        else
          head.each_index.min_by { |i| (head[i].center - cell.center).abs }
        end
      end

      # Index where the preface ends: the start of the page that holds the first
      # table row (the table's title and column header open that page in the
      # official PDFs), else, when the preface shares that page, the block of
      # non-blank lines that holds the row (its column header), else the end of
      # the text. `first_row` says whether a line starts a table row; it receives
      # the line (BIDI marks and presentation forms folded) and the folded lines
      # that follow it.
      def prose_stop(lines, start, &first_row)
        folded = lines.map { |l| l.gsub(BIDI, '').unicode_normalize(:nfkc) }
        hit = (start...folded.size).find { |i| !folded[i].strip.empty? && first_row.call(folded[i], folded[i + 1, 60]) }
        return lines.size unless hit

        page = (start + 1..hit).to_a.reverse.find { |i| lines[i].start_with?("\f") }
        return page if page

        hit -= 1 while hit > start && !folded[hit - 1].strip.empty?
        hit
      end

      def unique_keys(rows)
        seen = Hash.new(0)
        rows.map do |row|
          seen[row.key] += 1
          seen[row.key] > 1 ? row.class.new("#{row.key}##{seen[row.key]}", row.text) : row
        end
      end
    end
  end
end
