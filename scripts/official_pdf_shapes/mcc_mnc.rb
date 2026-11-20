# frozen_string_literal: true

require_relative 'column_rows'

module OfficialPdfComparison
  module Shapes
    # E.212B has four code tables, read in order:
    #   main    "Country | Networks | MCC + MNC": a country heading is a line
    #           without a code set left of the network column ("country:<name>");
    #           a network row is keyed by its code ("505 01"), text = network.
    #   shared  MCC 901 networks, names in the first column ("shared:901 03").
    #   other   shared codes for other purposes ("other:902 01").
    #   extra   extra-territorial use: code in the middle of the line, with the
    #           country pair, MSIN ranges and operator around it
    #           ("extra:208 01"). The cells wrap differently in each PDF, so
    #           its text is the sorted words of the row.
    # A repeated key gets "#2". A name that wraps leaves its pieces above and
    # below the code line: a piece above a code-only line belongs to that row,
    # a piece directly below a row to that row. Lines without a code that
    # touch no row (headings, notes, forms) are not rows. The generated Arabic
    # PDF prints the pair as "MNC MCC" (bidi); the shape reads "MCC MNC".
    class MccMnc < Base
      include ColumnRows::Prose

      PUBLICATIONS = %w[T-SP-E.212B-2018].freeze

      HEAD_INDENT_SLACK = 4
      REPEATED_HEADER = 5
      MIDDLE = /\A\s*(?<left>\S.*?)\s{2,}(?<a>\d{3}) (?<b>\d{2,3})\s{2,}(?<rest>\S.*)\z/
      LEFT = /\A(?<indent>\s*)(?<a>\d{2,3}) (?<b>\d{2,3})(?:\s+(?<name>\S.*))?\z/
      RIGHT = /\A(?<indent>\s*)(?<name>\S.*?)\s+(?<a>\d{3}) (?<b>\d{2,3})\z/

      Entry = Struct.new(:kind, :code, :text, :indent, :raw)

      def rows(text)
        lines = ColumnRows.clean_lines(text)
        @swapped = swapped?(lines)
        @arabic = text.match?(/\p{Arabic}/)
        entries = classify(lines)
        build(from_table(entries))
      end

      def row_line?(line) = MIDDLE.match?(line) || !code_match(line).nil?

      private

      def swapped?(lines)
        lines.count { |l| l.match?(/\A\s*\d\d \d{3}(\s|\z)/) } >
          lines.count { |l| l.match?(/\A\s*\d{3} \d\d(\s|\z)/) }
      end

      # Page furniture and the table header repeated on every page are dropped
      # (a line that recurs REPEATED_HEADER times without a code is a header);
      # a break entry stops a wrapped name from running across them.
      def classify(lines)
        entries = lines.map { |raw| entry(raw) }
        @name_col = name_column(entries)
        headers = entries.select { |e| heading_line?(e) }.map(&:text).tally
        entries.map { |e| heading_line?(e) && headers[e.text] >= REPEATED_HEADER ? Entry.new(:break) : e }
      end

      def heading_line?(entry) = entry.kind == :piece && heading_column?(entry)

      def entry(raw)
        return Entry.new(:break) if raw.strip.empty? || raw.match?(ColumnRows::PAGE_NUMBER)

        if m = MIDDLE.match(raw)
          Entry.new(:middle, "#{m[:a]} #{m[:b]}", ColumnRows.squeeze("#{m[:left]} #{m[:rest]}"), 0, raw)
        elsif (code = code_match(raw))
          Entry.new(:code, code[:code], ColumnRows.squeeze(code[:name]), code[:indent], raw)
        else
          Entry.new(:piece, nil, ColumnRows.squeeze(raw), ColumnRows.indent(raw), raw)
        end
      end

      def code_match(raw)
        m = LEFT.match(raw) || RIGHT.match(raw)
        return unless m && m[:a].size + m[:b].size >= 5

        a, b = @swapped ? [m[:b], m[:a]] : [m[:a], m[:b]]
        { code: "#{a} #{b}", name: m[:name].to_s, indent: m[:indent].size }
      end

      # The most common indent of network names (the main table has by far the
      # most rows); country headings sit left of it.
      def name_column(entries)
        tally = entries.select { |e| e.kind == :code && !e.text.empty? }.map(&:indent).tally
        tally.max_by { |_, n| n }&.first || 0
      end

      # Everything before the table: drop it, keeping only the heading run
      # directly above the first row (the first country).
      def from_table(entries)
        first = entries.index { |e| e.kind != :piece && e.kind != :break }
        return entries unless first

        run = first
        run -= 1 while run.positive? && entries[run - 1].kind == :piece
        entries.drop(run)
      end

      def build(entries)
        @rows = []
        @section = 'main'
        @pending = []
        @contiguous = false
        @anchored = false
        @country_open = false
        entries.each do |e|
          case e.kind
          when :break then page_break
          when :piece then piece(e)
          else row(e)
          end
        end
        settle
        ColumnRows.unique_keys(@rows)
      end

      def page_break
        @note = false
        settle
        @contiguous = false
        @country_open = false
      end

      def row(entry)
        @note = false
        @country_open = false
        @section = entry.kind == :middle ? 'extra' : section_for(entry)
        if entry.kind == :code && entry.text.empty?
          code_only(entry)
        else
          settle
          entry = country_head(entry) if @section == 'main'
          add_row(entry.code, entry.text)
        end
      end

      # A name printed above its code line, possibly with a piece below the
      # row before: with two or more pieces waiting the first closes the
      # previous row and the rest start this one.
      def code_only(entry)
        if @pending.size >= 2 && @anchored && @rows.last
          closing = @pending.shift
          target = @rows.last
          target.text = ColumnRows.squeeze("#{target.text} #{closing.text}")
        end
        prefix = @pending.map(&:text).join(' ')
        @pending = []
        add_row(entry.code, prefix)
      end

      # A country name that wraps puts its last line left of the first
      # network of the next country ("of Macedonia   T-Mobile   294 01"); it
      # is split off at the gap before the network column. A line with no such
      # gap keeps the country words in the network name.
      def country_head(entry)
        return entry if @arabic || !heading_column?(entry)

        m = /\A\s*(?<head>\S.*?)\s{2,}(?<name>\S.*?)\s+\d{3} \d{2,3}\s*\z/.match(entry.raw)
        return entry unless m

        country(Entry.new(:piece, nil, ColumnRows.squeeze(m[:head]), 0, m[:head]))
        Entry.new(:code, entry.code, ColumnRows.squeeze(m[:name]), entry.indent, entry.raw)
      end

      def section_for(entry)
        return @section if @section == 'extra'
        return 'shared' if entry.code.start_with?('901 ') && (@section == 'shared' || @arabic || heading_column?(entry))
        return 'other' if %w[shared other].include?(@section)

        'main'
      end

      def heading_column?(entry) = entry.indent < @name_col - HEAD_INDENT_SLACK

      def add_row(code, text)
        text = ColumnRows.squeeze(@section == 'extra' ? text.split.sort.join(' ') : text)
        @rows << Row.new("#{@section}:#{code}", text)
        @contiguous = true
      end

      def piece(entry)
        @note = true if entry.text.start_with?('*')
        return if @note

        if @section == 'main' && country?(entry)
          settle
          country(entry)
        else
          @country_open = false
          @anchored = @contiguous if @pending.empty?
          @pending << entry
        end
      end

      def country?(entry)
        @arabic ? entry.raw.match?(/\p{Arabic}/) : heading_column?(entry)
      end

      def country(entry)
        if @country_open
          last = @rows.last
          last.text = ColumnRows.squeeze("#{last.text} #{entry.text}")
          last.key = "country:#{last.text}"
        else
          @rows << Row.new("country:#{entry.text}", entry.text)
        end
        @country_open = true
        @contiguous = false
      end

      # Pending pieces extend the row just above when nothing broke the run
      # between them; otherwise they are not table rows and are dropped.
      def settle
        target = @rows.last
        if @pending.any? && @anchored && target && !target.key.start_with?('country:')
          text = ColumnRows.squeeze("#{target.text} #{@pending.map(&:text).join(' ')}")
          target.text = @section == 'extra' ? text.split.sort.join(' ') : text
        end
        @pending = []
      end
    end
  end
end
