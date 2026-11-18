# frozen_string_literal: true

require "nokogiri"
require "digest"
require "ituob/support"

module Ituob
  module Models
    # Independent reader of Poppler's positioned XML for the printed 2011 list.
    # Coordinates describe the five printed columns; the seed/replay are not read.
    class F32PrintedList
      LANGUAGES = %i[fr en es].freeze
      NETWORK_CODE = /\A([A-Z]{2})(?:\s*-\s*){0,2}\z/
      OFFICE_CODE = /\A(?:[A-Z]{4}|--[A-Z]{2})\z/
      # Some printed rows carry the office suffix at the end of the name cell.
      INLINE_CODE = /\A(?<name>.*?)\s*(?<code>--[A-Z]{2})\z/
      # Poppler also joins a name cell with the 4-letter office code that follows it
      # ("Berat  ABBR"). It is a code only when it begins with a prefix the country
      # already uses (a printed network code or an office code printed earlier in
      # the country); a name such as "ALBA" or "KAFR EL DAWAR" is not.
      TRAILING_CODE = /\A(?:(?<name>.*?)\s+)?(?<code>[A-Z]{4})\z/

      def initialize(xml_path:, pdf_path:)
        @document = Nokogiri::XML(File.read(xml_path)) { |config| config.nonet }
        @rules = Ituob::Support::Yaml.safe_load_file(F32SeedBuilder::RULES_PATH)
        @pdf_path = pdf_path
        unless Digest::SHA256.file(pdf_path).hexdigest == @rules.fetch("source_sha256")
          raise "F32 printed source does not match the pinned official PDF"
        end
        pages = @document.xpath("//page").map { |page| page["number"].to_i }
        unless pages == (1..@rules.fetch("source_pages")).to_a
          raise "F32 positioned XML does not include every official source page"
        end
        @publication = F32SeedPublication.new(
          source_uri: @rules.fetch("source_uri"), source_sha256: Digest::SHA256.file(pdf_path).hexdigest,
          source_path: "T-SP-F.32-2011-PDF-E.pdf", source_position_on: @rules.fetch("position_on"),
          source_complete: false
        )
        @country_parts = []
        @networks = []
        @network_names = {}
        @current_network = nil
        @office_prefixes = []
        @pending_names = []
        @seen = {}
        @printed_office_rows = 0
        @source_row = 0
      end

      def parse
        fonts = @document.xpath("//fontspec").to_h { |font| [font["id"], font] }
        @document.xpath("//page").each do |page|
          @page = page["number"].to_i
          texts = page.xpath("./text")
          @publication.pages << F32PrintedPage.new(number: @page, text: texts.map(&:text).join("\n"))
          next unless texts.any? { |text| text.text.include?("Destination Indicators (DI) assigned to telegraph offices") }

          rows(texts, fonts).each { |row| consume_row(row) }
        end
        flush_cessation_note
        flush_unassigned
        raise "Printed F32 country heading is incomplete: #{@country_parts.inspect}" unless @country_parts.empty?
        represented = @publication.allocations.length + @publication.contexts.count do |context|
          %w[shared-indicator network-relative-office].include?(context.kind)
        end
        raise "Printed F32 office rows were not completely represented" unless represented == @printed_office_rows

        @publication.source_row_count = @source_row
        @publication.source_complete = true
        @publication
      end

      private

      def rows(texts, fonts)
        grouped = {}
        texts.each do |text|
          top = text["top"].to_i
          next unless top > 145 && top < 1180
          next if text.text.strip.empty?

          baseline = grouped.keys.find { |value| (value - top).abs <= 2 } || top
          grouped[baseline] ||= []
          grouped[baseline] << [text["left"].to_i, text.text.strip, fonts.fetch(text["font"])]
        end
        grouped.sort.map { |_top, row| row.sort_by(&:first) }
      end

      def data_font?(font)
        font["size"].to_i == 12 && font["family"].end_with?("+Arial")
      end

      # Some printed office names are set in bold Arial 12 ("RADIO/HPP", "ADEN").
      def bold_name_font?(font)
        font["size"].to_i == 12 && font["family"].end_with?("+Arial,Bold")
      end

      def consume_row(nodes)
        @source_row += 1
        full_width = nodes.select { |left, _text, font| left < 100 && data_font?(font) }
        text = full_width.map { |_left, value, _font| value }.join(" ")
        if text.match?(/The telegrams? service\s*is\s*no longer/)
          flush_cessation_note
          @cessation_note = text.sub(/\A\s*(?:1|!)\)\s*/, "")
          return
        elsif @cessation_note && !text.empty? && !text.match?(/\A\d+\)/)
          @cessation_note << " " << text
          return
        end
        flush_cessation_note
        heading = nodes.filter_map do |left, text, font|
          text if left < 225 && font["family"].include?("Bold") && font["size"].to_i >= 10
        end.join(" ")
        consume_country(heading) unless heading.empty?
        nodes.each do |left, text, font|
          next unless left >= 225 && left < 530 && data_font?(font)
          # Some country-heading rows merge the code into the empty ROA cell.
          # Other ROA-column text must not expand the canonical network scope.
          next if left < 430 && heading.empty?

          match = text.match(NETWORK_CODE)
          next unless match

          prefix = match[1]
          @current_network = prefix
          @network_names[prefix] ||= +""
          @networks << prefix unless @networks.include?(prefix)
          code = left < 430 ? "#{prefix}- -" : text
          context("network", F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country, network_code: code,
                                           network_roa: @network_names[prefix]),
                  "Printed network code; the first two letters identify the network (source page 2).")
        end
        roa = nodes.filter_map do |left, text, font|
          next unless left >= 225 && left < 430 && data_font?(font)
          next if !heading.empty? && text.match?(NETWORK_CODE)

          text
        end.join(" ")
        if @current_network && !roa.empty?
          buffer = @network_names.fetch(@current_network)
          unless buffer.include?(roa)
            buffer << " " unless buffer.empty?
            buffer << roa
          end
        end
        names = nodes.filter_map { |left, text, font| text if left >= 530 && left < 700 && (data_font?(font) || bold_name_font?(font)) }
        inline_codes = []
        names = names.filter_map do |name|
          match = name.match(INLINE_CODE)
          next name unless match

          inline_codes << match[:code]
          match[:name] unless match[:name].empty?
        end
        names = names.filter_map do |name|
          match = name.match(TRAILING_CODE)
          next name unless match && printed_network_prefix?(match[:code])

          inline_codes << match[:code]
          match[:name] unless match[:name].to_s.empty?
        end
        codes = nodes.filter_map do |left, text, font|
          next unless left >= 700 && data_font?(font)
          raise "Unparsed F32 office-code cell on page #{@page}: #{text}" unless text.match?(OFFICE_CODE)
          text
        end
        codes.unshift(*inline_codes)
        if names.any? { |name| name.include?("-->") }
          context("alias", F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country,
                                           telegraph_office_name: MultilingualString.new(en: names.join(" "))))
        else
          @pending_names.concat(names)
        end
        codes.each { |code| consume_office(code) }
      end

      def flush_cessation_note
        return unless @cessation_note

        target = @publication.contexts.find do |record|
          record.kind == "network" && record.entry.country_or_area.equal?(@country)
        end&.entry
        raise "Printed F32 cessation note has no network on page #{@page}" unless target

        target.network_code_note = MultilingualString.new(en: @cessation_note, fr: @cessation_note, es: @cessation_note)
        @cessation_note = nil
      end

      def printed_network_prefix?(code)
        (@networks + @office_prefixes).include?(code[0, 2])
      end

      def consume_country(heading)
        if @country_parts.empty?
          flush_unassigned
          same_country = @country && @country.fr.to_s.upcase.start_with?(heading.upcase)
          unless same_country
            @networks = []
            @network_names = {}
            @current_network = nil
            @office_prefixes = []
          end
          @country = MultilingualString.new
          layout = @rules.fetch("country_layouts").find { |rule| rule.fetch("first") == heading }
          @country_lines = layout ? layout.fetch("lines") : [1, 1, 1]
        end
        @country_parts << heading
        offset = 0
        LANGUAGES.zip(@country_lines).each do |language, length|
          @country.public_send("#{language}=", @country_parts.slice(offset, length).to_a.join(" "))
          offset += length
        end
        if @country_parts.length == @country_lines.sum
          context("heading", F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country), "Printed country/geographical-area heading.")
          @country_parts = []
        end
      end

      def consume_office(code)
        raise "Printed F32 office has no country on page #{@page}" unless @country
        @printed_office_rows += 1
        entry = F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country,
                                telegraph_office_name: MultilingualString.new(en: @pending_names.join(" ")),
                                office_code: code, source_page: @page, source_row: @source_row)
        @pending_names = []
        if code.start_with?("--")
          if @networks.length == 1
            entry.office_code = @networks.first + code.delete_prefix("--")
          else
            context("network-relative-office", entry,
                    "Printed office suffix with multiple network codes; no single full indicator is asserted.")
            return
          end
        end
        entry.network_code = entry.office_code[0, 2]
        @office_prefixes << entry.network_code unless @office_prefixes.include?(entry.network_code)
        entry.network_roa = @network_names[entry.network_code]
        entry.network_codes = @networks.dup
        if @seen[entry.office_code]
          context("shared-indicator", entry, "Another office served by this printed destination indicator.")
        else
          @publication.allocations << entry
          @seen[entry.office_code] = true
        end
      end

      def flush_unassigned
        return if @pending_names.empty?
        entry = F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country,
                                telegraph_office_name: MultilingualString.new(en: @pending_names.join(" ")))
        context("printed-unassigned", entry, "Printed name without an assigned office-code cell.")
        @pending_names = []
      end

      def context(kind, entry, explanation = nil)
        entry.source_page = @page
        entry.source_row = @source_row
        @publication.contexts << F32SeedContext.new(ob_issue_no: 980,
          kind: kind, entry: entry, source_uri: @publication.source_uri, source_page: @page,
          source_path: @publication.source_path, source_row: @source_row,
          network_codes: @networks.dup, related_office_code: entry.office_code, explanation: explanation
        )
      end
    end
  end
end
