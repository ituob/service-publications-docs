# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-F.68-2011: telex destination codes. Four small tables share the
    # publication, each with its own row: the TDC list (code, network code,
    # name), the abbreviations, appendix 1 (TNIC to telegram network codes) and
    # appendix 2 (OB number and country, two pairs per line). The key carries
    # the table so equal codes in different tables never collide.
    class F68TelexCodes < Base
      PUBLICATIONS = %w[T-SP-F.68-2011].freeze
      TDC = /\A(\d{1,3}(?:-\d{3})?)(?: ?(?:[a-z]{1,2}\)|[ªº]\)?))?\z/
      HEADINGS = {
        abbr: /\A(?:\d\.\s+)?(?:ABBREVIATIONS|ABRÉVIATIONS|ABREVIATURAS)\z/,
        skip: /\A(?:\d\.\s+)?(?:AMENDMENTS|AMENDEMENTS|ENMIENDAS)\z/,
        appx1: /\A(?:APPENDIX 1|APPENDICE 1|APÉNDICE 1|Annex A|Annexe A|Anexo A)\z/,
        appx2: /\A(?:APPENDIX 2|APPENDICE 2|APÉNDICE 2|Annex B|Annexe B|Anexo B)\z/
      }.freeze
      ABBR_COL = 8
      TABLES = %w[TDC TNIC OB ABBR].freeze
      FOOTNOTE_MARK = /(?<=[[:alpha:]\)])\d\)\z|\s[a-z]\)\z/

      # The preface runs from "Notes from TSB" (the official PDF says "Notes",
      # not Base's "Note") to the first TDC table header; everything after is
      # table rows, appendices and footnotes, which rows() covers.
      NOTES = /\A(?:\d\.\s+)?(?:Notes from TSB|Notes du TSB|Notas de la TSB)\z/
      TABLE_HEAD = /\A\s*(?:TDC|CTD)\s+(?:TNIC|CIRT)\b/

      def prose_start(lines, _lang) = lines.index { |l| l.strip.match?(NOTES) } || 0

      def prose_stop(lines, start)
        lines.index.with_index { |l, i| i > start && l.match?(TABLE_HEAD) } || lines.size
      end

      def rows(text)
        mode = :tdc
        out = []
        G3Support.lines(text).each do |line|
          next if line.strip.empty? || G3Support.furniture?(line)

          if (heading = HEADINGS.find { |_, re| line.strip.match?(re) })
            mode = heading.first
            next
          end
          send(:"read_#{mode}", line, out) unless mode == :skip
        end
        canonical(out)
      end

      private

      # The tables come in a different order in the two PDFs (the official
      # abbreviations come last, the generated ones before the appendices), and
      # the two columns of appendix 2 read in a different order. Neither is a
      # row difference, so rows are returned table by table, appendix 2 sorted.
      def canonical(out)
        rows = out.map { |r| Row.new(r.key, G3Support.squish(r.text).sub(FOOTNOTE_MARK, '')) }
        rows.each_with_index.sort_by { |r, i| [TABLES.index(r.key.split.first), r.key.start_with?('OB') ? [r.key, r.text] : [i]] }.map(&:first)
      end

      def read_tdc(line, out)
        cells = G3Support.cells_at(line).map(&:first)
        return if cells.all? { |c| c.match?(/\A[1-3]\z/) }

        if cells.first.match?(TDC)
          tnic, name = tnic_and_name(cells.drop(1))
          out << Row.new("TDC #{cells.first[TDC, 1]}", [tnic, name].compact.join(' '))
        elsif cells.size == 1 && (m = cells.first.match(/\A([A-Z]{1,2})(?:[a-z]\))?\z/)) && out.last&.key&.start_with?('TDC')
          # a second network code printed under the first ("RU" over "SU")
          out.last.text = out.last.text.sub(/\A([A-Z]{1,2}) /, "\\1 / #{m[1]} ")
        elsif cells.first.match?(/\A[a-z]\)\z/) && out.last&.text&.empty? && cells.size > 1
          out.last.text = cells.drop(1).join(' ')
        end
      end

      def tnic_and_name(rest)
        return [nil, rest.join(' ')] unless rest.size > 1 && rest.first.match?(/\A[A-Z]{1,2}\z/)

        [rest.first, rest.drop(1).join(' ')]
      end

      def read_abbr(line, out)
        cells = G3Support.cells_at(line)
        if cells.first.last <= ABBR_COL && cells.size > 1
          out << Row.new("ABBR #{cells.first.first}", cells.drop(1).map(&:first).join(' '))
        elsif out.any? { |r| r.key.start_with?('ABBR') }
          out.last.text = "#{out.last.text} #{cells.map(&:first).join(' ')}"
        end
      end

      def read_appx1(line, out)
        cells = G3Support.cells_at(line).map(&:first)
        if cells.size == 3 && cells.first.match?(/\A[A-Z]\z/)
          out << Row.new("TNIC #{cells.first}", cells.drop(1).join(' '))
        elsif cells.size == 1 && out.last&.key&.start_with?('TNIC')
          out.last.text = "#{out.last.text} #{cells.first}"
        end
      end

      # Two columns of "OB number, country"; a wrapped country continues on the
      # next line under its own column.
      def read_appx2(line, out)
        cells = G3Support.cells_at(line)
        return if cells.all? { |t, _| t.match?(/\A(?:OB|No\.?|N[°o.]+)\z/i) }

        left = @appx2_left ||= []
        cells.each_with_index do |(text, col), i|
          if text.match?(/\A\d{3}\z/) && cells[i + 1]
            row = Row.new("OB #{text}", cells[i + 1].first)
            out << row
            (col < 40 ? left : @appx2_right ||= []).replace([row])
          elsif !text.match?(/\A\d{3}\z/) && i.positive? && cells[i - 1].first.match?(/\A\d{3}\z/)
            next
          elsif text !~ /\A\d{3}\z/ && out.any? { |r| r.key.start_with?('OB ') }
            side = col < 40 ? left : @appx2_right
            side&.first&.text = "#{side.first.text} #{text}"
          end
        end
      end
    end
  end
end
