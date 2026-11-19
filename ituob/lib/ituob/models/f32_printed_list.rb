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
      # As printed: the French and Spanish editions print one relative code
      # with a single hyphen.
      PRINTED_CODE_BODY = /(?:[A-Z]{4}|-{1,2}[A-Z]{2})/
      PRINTED_CODE_WITH_MARK = /\A(?<code>#{PRINTED_CODE_BODY})(?:\s*(?<mark>\d+\)))?\z/
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

          rows(texts, fonts).each do |row|
            consume_row(row)
            retain_printed_row(row)
          end
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
        retain_other_editions
        @publication.source_row_count = @source_row
        @publication
      end

      private

      # The other editions print a name a few points off the line of its code.
      def rows(texts, fonts, tolerance: 2)
        grouped = {}
        texts.each do |text|
          top = text["top"].to_i
          next unless top > 145 && top < 1180
          next if text.text.strip.empty?

          baseline = grouped.keys.find { |value| (value - top).abs <= tolerance } || top
          grouped[baseline] ||= []
          grouped[baseline] << [visible_left(text), text.text.strip, fonts.fetch(text["font"]), text["width"].to_i]
        end
        grouped.sort.map { |_top, row| row.sort_by(&:first) }
      end

      # Poppler folds a leading gap into the node: its `left` is where the blank
      # starts (often the end of the previous cell), not where the printed text
      # does, and its width includes the gap. A short text inside a node much
      # wider than the text needs starts at the next printed column; otherwise
      # only the few leading blanks shift it. Measured against the pdftotext
      # word boxes of the three printed editions.
      COLUMN_STARTS = [234, 447, 540, 752].freeze
      CHARACTER_WIDTH = 5.5
      FOLDED_GAP = 100
      BLANK_WIDTH = 4
      SHORT_TEXT = 14

      def visible_left(text)
        left = text["left"].to_i
        raw = text.text
        visible = raw.strip
        gap = raw.length - raw.lstrip.length
        return left if gap.zero? || visible.empty?

        if visible.length <= SHORT_TEXT && text["width"].to_i - raw.length * CHARACTER_WIDTH > FOLDED_GAP &&
            (start = COLUMN_STARTS.find { |column| column >= left + 10 })
          return start
        end

        left + gap * BLANK_WIDTH
      end

      # Keep the positioned display independently of allocation inference. Poppler
      # can merge neighboring cells, notes span columns, and country-column text
      # can be a subdivision rather than a new country. None may be discarded.
      def retain_printed_row(nodes)
        cells = Array.new(5) { [] }
        # A name that ends in a code-shaped word ("UYUNI") is not a joined node
        # when the row also carries its own code node.
        code_node = nodes.any? { |left, text, _font| left >= 700 && text.match?(PRINTED_CODE_WITH_MARK) }
        nodes.each do |left, text, _font|
          column = [225, 430, 530, 700].count { |boundary| left >= boundary }
          # The PDF extractor sometimes combines ROA and code into one node.
          if column < 2 && (match = text.match(/\A(?:(?<label>.*?)\s+)?(?<code>[A-Z]{2}\s*-\s*-?)\z/))
            cells[column] << match[:label] unless match[:label].to_s.empty?
            cells[2] << match[:code]
          elsif column == 3 && !code_node && (match = text.match(/\A(?<name>.*?)\s*(?<code>--[A-Z]{2}|[A-Z]{4})\z/)) &&
              (match[:code].start_with?("--") || @seen[match[:code]])
            cells[3] << match[:name] unless match[:name].empty?
            cells[4] << match[:code]
          else
            cells[column] << text
          end
        end
        values = cells.map { |parts| parts.join(" ") }
        heading = nodes.any? do |left, _text, font, width|
          left < 225 && left + width < 530 && font["family"].include?("Bold") && font["size"].to_i >= 10
        end
        indicator = nodes.any? do |left, text, _font, _width|
          (left >= 700 && text.match?(OFFICE_CODE)) || (left >= 430 && text.match?(NETWORK_CODE))
        end
        full_width = !indicator && nodes.any? do |left, text, _font, width|
          left < 225 && left + width > 530 && text.split.size >= 8
        end
        @printed_note = false if heading || values[1..].any? { |value| !value.empty? }
        @printed_note = true if full_width || values.first.match?(/\A(?:\d+|!)\)/)
        values = [nodes.map { |_left, text, _font, _width| text }.join(" ")] if @printed_note
        unless @source_language || values.length == 1 || values[4].empty?
          office = @publication.allocations.last
          office = @publication.contexts.last&.entry unless office&.source_row == @source_row
          values[4] = office.office_code if office&.source_row == @source_row && office.office_code
        end
        # A footnote marker printed beside the code ("ESTT 1)") is its own row,
        # as the English edition prints it, so the code cell holds only the code.
        mark = nil
        if values.length == 5 && (split = values[4].match(PRINTED_CODE_WITH_MARK)) && split[:mark]
          values[4] = split[:code]
          mark = split[:mark]
        end
        retain_row(values, heading)
        retain_row(["", "", "", "", mark], false) if mark
      end

      def retain_row(values, heading)
        entry = F32TDIEntry.new(_class: "F32TDIEntry", country_or_area: @country,
          source_cells: values, source_language: @source_language || "en", source_heading: heading)
        context("printed-row", entry, "Positioned source cells in printed reading order.")
      end

      def retain_other_editions
        @rules.fetch("printed_editions").each do |language, edition|
          fixture = File.join(File.dirname(@pdf_path), edition.fetch("fixture"))
          unless Digest::SHA256.file("#{fixture}.pdf").hexdigest == edition.fetch("source_sha256")
            raise "F32 #{language} printed source does not match the pinned official PDF"
          end
          document = Nokogiri::XML(File.read("#{fixture}.xml")) { |config| config.nonet }
          unless document.xpath("//page").map { |page| page["number"].to_i } == (1..edition.fetch("source_pages")).to_a
            raise "F32 #{language} positioned XML does not include every official source page"
          end
          fonts = document.xpath("//fontspec").to_h { |font| [font["id"], font] }
          @source_language = language
          @country = nil
          @printed_note = false
          document.xpath("//page").each do |page|
            next unless page.xpath("./text").any? { |text| text.text.include?(edition.fetch("title")) }

            @page = page["number"].to_i
            rows(page.xpath("./text"), fonts, tolerance: 3).each do |row|
              @source_row += 1
              first = @publication.contexts.size
              retain_printed_row(row)
              @publication.contexts[first..].each do |record|
                record.source_uri = edition.fetch("source_uri")
                record.source_path = "T-SP-F.32-2011-PDF-#{language == "fr" ? "F" : "S"}.pdf"
              end
            end
          end
        end
        join_wrapped_office_names
        align_printed_codes
      end

      # A coast-station name printed on two lines, the second carrying the code
      # ("Palo Alto, California" / "Radio/KFS UIMS"), is one cell. Only a line
      # that also carries its network's administration text is joined: other
      # name-only lines are separate printed aliases of the next office.
      def join_wrapped_office_names
        records = @publication.contexts.select { |record| record.kind == "printed-row" }
        joined = []
        records.each_cons(2) do |first, second|
          next if joined.include?(first)

          above = first.entry
          below = second.entry
          next unless wrapped_office_name?(above, below)

          above.source_cells[3] = "#{above.source_cells[3]} #{below.source_cells[3]}"
          above.source_cells[4] = below.source_cells[4]
          joined << second
        end
        @publication.contexts.reject! { |record| joined.include?(record) }
      end

      def wrapped_office_name?(above, below)
        above.source_language == below.source_language && above.source_page == below.source_page &&
          above.source_cells.length == 5 && below.source_cells.length == 5 &&
          !above.source_cells[1].empty? && !above.source_cells[3].empty? && above.source_cells[4].empty? &&
          below.source_cells[0..2].all?(&:empty?) && !below.source_cells[3].empty? &&
          below.source_cells[4].match?(PRINTED_CODE_WITH_MARK)
      end

      # The English edition resolves a network-relative code ("--AC") to the
      # indicator it stands for. The French and Spanish editions print the same
      # offices in the same order, so each one takes the English code at its
      # aligned position. An office only one edition prints keeps its own code.
      def align_printed_codes
        entries = @publication.contexts.select { |record| record.kind == "printed-row" }.map(&:entry)
        office_rows = entries.group_by(&:source_language).transform_values do |rows|
          rows.select { |row| row.source_cells.length == 5 && row.source_cells[4].match?(PRINTED_CODE_WITH_MARK) }
        end
        english = office_rows.fetch("en")
        %w[fr es].each do |language|
          printed = office_rows.fetch(language)
          pairs = longest_common_positions(english.map { |row| row.source_cells[4][-2, 2] },
            printed.map { |row| row.source_cells[4][-2, 2] })
          missing = english.size - pairs.size
          raise "F32 #{language} printed list does not align with the English list (#{missing} offices)" if missing.positive?

          pairs.each { |english_at, printed_at| printed[printed_at].source_cells[4] = english[english_at].source_cells[4] }
        end
      end

      def longest_common_positions(left, right)
        lengths = Array.new(left.size + 1) { Array.new(right.size + 1, 0) }
        left.each_index do |i|
          right.each_index do |j|
            lengths[i + 1][j + 1] = left[i] == right[j] ? lengths[i][j] + 1 : [lengths[i][j + 1], lengths[i + 1][j]].max
          end
        end
        pairs = []
        i = left.size
        j = right.size
        while i.positive? && j.positive?
          if left[i - 1] == right[j - 1]
            pairs.unshift([i - 1, j - 1])
            i -= 1
            j -= 1
          elsif lengths[i - 1][j] >= lengths[i][j - 1]
            i -= 1
          else
            j -= 1
          end
        end
        pairs
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
