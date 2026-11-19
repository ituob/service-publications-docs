# frozen_string_literal: true

require_relative 'base'
require_relative 'g3_support'

module OfficialPdfComparison
  module Shapes
    # T-SP-M.1400-2014: the list of ITU carrier codes. A row is one company: a
    # country cell ("Albania (Republic of) / ALB", wrapping over up to four
    # lines at the left margin), the company name and address, the carrier code
    # and the contact lines. The cells of a row interleave line by line in the
    # layout text and wrap differently in each renderer, so a row is the bag of
    # its words (see G3Support.word_bag), keyed by the ISO 3166 alpha-3 code of
    # its country cell. Rows are returned in reading order; a country with
    # several companies has several rows with the same key.
    #
    # Left-to-right layouts only (E, F, S, R, C). The Arabic layout prints the
    # country cell at the right margin, which this shape does not read.
    class M1400CarrierCodes < Base
      PUBLICATIONS = %w[T-SP-M.1400-2014].freeze
      COUNTRY_START = %r{\s/\z|\s/\s?[A-Z]{3}\z}
      # The ISO code ends the country cell, or the renderer ran the next cell
      # into it with one space ("Barbados / BRB Cable and Wireless").
      ISO = %r{/\s?([A-Z]{3})\b|\A([A-Z]{3})(?:\s|\z)}
      HEADER = /\A(?:Country or area|Pays ou zone|País o zona|Страна или зона|国家或区域|Note\b|Nota\b|NOTE\b|NOTA\b|Примечание|ПРИМЕЧАНИЕ|注)/
      TITLE = /List of ITU Carrier Codes|Liste des codes de transporteur|Lista de códigos de operador|Список кодов МСЭ|国际电联电信运营商代码/i

      def rows(text)
        pages = text.split("\f")
        last = pages.rindex { |p| p.lines.any? { |l| country_cell(l)&.match?(COUNTRY_START) } }
        return [] unless last

        blocks = []
        done = true
        started = false
        in_header = false
        pages.first(last + 1).each do |page|
          G3Support.lines(page).each do |line|
            next if line.strip.empty? || G3Support.furniture?(line) || line.match?(TITLE)

            cell = country_cell(line)
            started ||= cell&.match?(COUNTRY_START)
            next unless started

            if cell&.match?(HEADER)
              in_header = true
              next
            end
            next if in_header && !cell

            in_header = false
            if cell
              blocks << { country: [], lines: [] } if done
              blocks.last[:country] << cell
              done = iso_of(cell) ? true : false
            end
            blocks.last[:lines] << line
          end
        end
        blocks.filter_map { |b| row(b) }
      end

      private

      def country_cell(line)
        return unless line.match?(/\A\S/)

        G3Support.cells_at(line).first&.first
      end

      def iso_of(cell)
        m = cell.match(ISO)
        m && (m[1] || m[2])
      end

      def row(block)
        iso = block[:country].filter_map { |c| iso_of(c) }.last
        iso && Row.new(iso, G3Support.squish(block[:lines].join(' ')))
      end
    end
  end
end
