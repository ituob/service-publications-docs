# frozen_string_literal: true

require_relative 'base' if File.exist?(File.join(__dir__, 'base.rb'))
require_relative 'g1_support'

module OfficialPdfComparison
  module Shapes
    # The E.164 annexes that list one country per row: E.164B (mobile access
    # codes), E.164C (dialling procedures) and E.164D (assigned country codes).
    # B and C start a row at a country name followed by a numeric code cell; D
    # starts it at the code cell followed by the country. A row is the first
    # line plus the wrap lines under it; its text is column-wise (see
    # G1Support.column_text).
    class CountryCodeTable < Base
      PUBLICATIONS = %w[T-SP-E.164B-2012 T-SP-E.164C-2011 T-SP-E.164D-2016].freeze
      CODE = /\A\d{1,3}(?:\(.*\))?\z/
      MAX_WRAP = 6

      def rows(text)
        lines = G1Support.body_lines(mirror_letters(text))
        cands = lines.filter_map { |l| (r = row_key(G1Support.cells(l.text))) && [l, *r] }
        # a page with a table has many rows; the few numbered paragraphs of the
        # preface do not make a column
        by_page = cands.group_by { |l, _, _| l.page }
        cols = by_page.select { |_, c| c.size >= 8 }.transform_values { |c| mode(c.map { |_, _, start| start }) }
        # the short last page of a table has few rows: it keeps the column of the
        # table's other pages (the preface's own pages have none of it)
        table_col = cols.values.then { |v| v.any? ? mode(v) : nil }
        by_page.each_key { |page| cols[page] ||= table_col if table_col && by_page[page].count { |_, _, st| (st - table_col).abs <= 6 } >= 2 }
        accepted = cands.select { |l, _, start| cols[l.page] && (start - cols[l.page]).abs <= 6 }.to_h { |l, key, _| [l, key] }
        rows = []
        gap = 0
        page = nil
        lines.each do |line|
          cells = G1Support.cells(line.text)
          # the blank lines around a page break (footer and header, both cut out)
          # do not separate a name from its continuation on the next page
          gap = 0 if line.page != page
          page = line.page
          if accepted.key?(line)
            rows << { key: accepted[line], lines: [line] }
            gap = 0
          elsif cells.empty?
            gap += 1
          elsif rows.any? && continuation?(rows.last, cells, gap)
            rows.last[:lines] << line
            gap = 0
          elsif rows.any?
            rows.last[:closed] = true
          end
        end
        heads = G1Support.page_heads(rows.map { |r| r[:lines].first }) { |cells| split_code(cells) }
        G1Support.unique_keys(rows.map { |r| Row.new(r[:key], G1Support.column_text(r[:lines], heads, align: :overlap) { |cells| split_code(cells) }) })
      end

      # a table row with at least seven more in its code column within the next
      # forty lines (the numbered paragraphs of the preface, one of which may
      # look like a row, never make a column of them)
      def prose_stop(lines, start)
        G1Support.prose_stop(lines, start) do |line, following|
          key, col = row_key(G1Support.cells(line))
          key && following.first(40).count { |l| (r = row_key(G1Support.cells(l))) && (r[1] - col).abs <= 6 } >= 7
        end
      end

      private

      # Arabic words with their letters sorted: the official PDF's text layer
      # holds some letters in another order than the generated one (a font
      # mapping artefact), so only the letters can be compared
      def mirror_letters(text)
        text.gsub(G1Support::BIDI, '').unicode_normalize(:nfkc).gsub(/[\u0600-\u06FF]+/) { |w| w.chars.sort.join }
      end

      def mode(values) = values.tally.max_by { |_, n| n }.first

      # [key, code column start] of a row's first line: country name then code
      # (B, C), code then country name (D) or, right to left, name then code at
      # the line's end (the Arabic D)
      def row_key(cells)
        cells = split_code(cells)
        return unless cells.size >= 2

        name, code = if cells[0].text =~ CODE then [cells[1], cells[0]]
                     elsif cells[1].text =~ CODE then [cells[0], cells[1]]
                     elsif cells[-1].text =~ CODE then [cells[-2], cells[-1]]
                     end
        return unless code && name.text =~ /\A[[:alpha:]]/ && name.text !~ /\A(?:annex|annexe|anexo)\b/i

        # the name wraps at a hyphen in one PDF and not in the other: key on the part before it
        ["#{code.text}|#{name.text.split.first.sub(/-.*\z/, '')}", code.start]
      end

      # a long country name leaves one space before its code ("China (People's
      # Republic of) 86"), and a code followed by one space and a text is two cells
      def split_code(cells)
        if cells.any? && (m = cells[0].text.match(/\A([[:alpha:]].*[[:alpha:])])\s(\d{1,3}(?:\([^)]*\))?)\z/))
          [G1Support::Cell.new(m[1], cells[0].start), G1Support::Cell.new(m[2], cells[0].start + m[1].size + 1), *cells.drop(1)]
        elsif cells.size == 2 && (m = cells[1].text.match(/\A(\d{1,3}(?:\([^)]*\))?)\s+(\S.*)\z/))
          [cells[0], G1Support::Cell.new(m[1], cells[1].start), G1Support::Cell.new(m[2], cells[1].start + m[1].size + 1)]
        else
          cells
        end
      end

      def continuation?(row, cells, gap)
        # the footnotes under the table start with a rule of underscores
        return false if row[:closed] || row[:lines].size > MAX_WRAP || gap > 1 || cells.first.text.start_with?('____')

        # a wrap line holds no new code and sits in the row's own columns
        head = G1Support.cells(row[:lines].first.text)
        cells.first.start >= head.first.start && cells.none? { |c| c.text =~ /\A(?:annex|annexe|anexo)\b/i }
      end
    end
  end
end
