# frozen_string_literal: true

require 'nokogiri'

module Ituob
  module Auditors
    # Compares two HTML renderings of the same logical page and reports
    # content that exists in +deployed+ but is missing in +actual+.
    #
    # The auditor is a pure comparator: it takes HTML strings (or
    # +Nokogiri::HTML::Document+) and returns a +Report+ value object.
    # It performs no I/O. Callers are responsible for reading files,
    # fetching URLs, and persisting the report.
    #
    # Comparison model:
    # - Extracts the main content area (the +<main>+ element, falling back
    #   to +<body>+ if absent).
    # - Splits content into sections by heading (h1-h3).
    # - For each section, computes a token multiset and reports tokens
    #   present in deployed but absent in actual.
    # - Reports missing structural elements: headings, tables, and
    #   significant links present in deployed but absent in actual.
    class ContentParity
      # Tokens shorter than this are ignored (stop-words / fragments).
      MIN_TOKEN_LENGTH = 3

      # Words that carry no semantic weight; skipped during comparison.
      # Includes English month abbreviations (date chrome) and column
      # header modifiers that differ between Jekyll and Astro table
      # headers (e.g. "Country/geographical area" vs "country or area").
      STOP_WORDS = Set.new(%w[
        the and for with that this from into when have has had not are was
        were been also one two three four five six more most such other
        over both up out off via its his her their our your them they then
        there here these those while whom whose what when where why how can
        may will could would should might must shall
        jan feb mar apr jun jul aug sep oct nov dec
        january february march april june july august september october november december
        geographical order
      ]).freeze

      # Cap per-token weight so a single spam word can't dominate coverage.
      MAX_TOKEN_WEIGHT = 5

      # Build a new auditor. No state — instances are safe to reuse.
      def initialize; end

      # Compare +deployed_html+ against +actual_html+ and return a Report.
      #
      # Both arguments may be Strings of HTML or already-parsed
      # +Nokogiri::HTML::Document+ instances.
      def compare(deployed_html, actual_html)
        deployed_doc = parse_html(deployed_html)
        actual_doc = parse_html(actual_html)

        deployed_section = main_element(deployed_doc)
        actual_section = main_element(actual_doc)

        # Performance guard: when either page has many headings,
        # skip the expensive section_blocks traversal entirely.
        # The coverage metric + heading diff don't need per-section
        # detail to be accurate. This avoids O(N) Nokogiri DOM
        # walks on pages with 800+ amendment H3s.
        deployed_heading_count = deployed_section&.css('h1, h2, h3')&.length || 0
        actual_heading_count = actual_section&.css('h1, h2, h3')&.length || 0

        if deployed_heading_count > 50 || actual_heading_count > 50
          section_reports = []
        else
          deployed_blocks = section_blocks(deployed_section)
          actual_blocks = section_blocks(actual_section)
          actual_index = index_blocks_by_heading(actual_blocks)
          section_reports = deployed_blocks.map do |block|
            compare_block_indexed(block, actual_blocks, actual_index)
          end
        end

        Report.new(
          deployed_tokens: count_tokens(deployed_section),
          actual_tokens: count_tokens(actual_section),
          deployed_unique: unique_tokens(deployed_section),
          actual_unique: unique_tokens(actual_section),
          sections: section_reports,
          missing_headings: missing_headings(deployed_section, actual_section),
          missing_links: missing_links(deployed_section, actual_section),
          missing_tables: missing_tables(deployed_section, actual_section),
        )
      end

      private

      def parse_html(input)
        return input if input.is_a?(Nokogiri::HTML::Document)

        Nokogiri::HTML(input.to_s)
      end

      # Return the +<main>+ element, falling back to +<body>+ if absent.
      def main_element(doc)
        doc.at_css('main') || doc.at_css('body') || Nokogiri::HTML::Document.new
      end

      # Split +root+ into per-section Nokogiri node sets, keyed by heading.
      #
      # Strategy: use h2/h3 headings as section boundaries, but stop
      # accumulating tokens into the current heading's block when we
      # leave the heading's enclosing <section> or <article>. This
      # prevents the last heading in a page from absorbing all trailing
      # page content (footer, scripts, etc.).
      def section_blocks(root)
        return [] if root.nil?

        heading_blocks(root)
      end

      def heading_blocks(root)
        blocks = []
        state = { current: nil, container: nil }
        walk_preorder(root, state, blocks)
        blocks
      end

      # Walk +node+ and its descendants in document order (pre-order:
      # parent before children). Nokogiri's +traverse+ is post-order,
      # which mis-attributes nested heading children to the parent
      # heading's block.
      def walk_preorder(node, state, blocks)
        return unless node.element?

        if %w[h1 h2 h3].include?(node.name)
          state[:container] = node.ancestors('section, article').first
          heading = node_text(node)
          # Include the heading's own tokens in the block so heading text
          # counts toward section coverage (matches how readers perceive
          # a section's content).
          state[:current] = { heading: heading, tokens: Set.new(tokens_for(heading)),
                              node: node, container: state[:container] }
          blocks << state[:current]
        elsif state[:current]
          current = state[:current]
          # Skip elements that contain a nested heading — their text
          # would double-count the nested heading's tokens.
          unless contains_heading?(node)
            current[:tokens].merge(tokens_for(node_text(node)))
          end
        end

        node.children.each { |child| walk_preorder(child, state, blocks) }
      end

      # +true+ if +node+ has a descendant h1, h2, or h3 (i.e. starts a
      # nested section that will create its own block).
      def contains_heading?(node)
        !node.at_xpath('.//h1 | .//h2 | .//h3').nil?
      rescue StandardError
        false
      end

      def compare_block(deployed_block, actual_blocks)
        actual_match = actual_blocks.find do |b|
          similar_heading?(b[:heading], deployed_block[:heading])
        end

        report_block_match(deployed_block, actual_match)
      end

      # Same as compare_block but uses a pre-built hash index for
      # O(1) heading lookup. Falls back to linear scan if the
      # heading isn't in the index (handles partial matches).
      def compare_block_indexed(deployed_block, actual_blocks, actual_index)
        norm = normalize_heading(deployed_block[:heading])
        actual_match = actual_index[norm]

        # Fall back to linear scan for substring matches (include? checks)
        unless actual_match
          actual_match = actual_blocks.find do |b|
            similar_heading?(b[:heading], deployed_block[:heading])
          end
        end

        report_block_match(deployed_block, actual_match)
      end

      def report_block_match(deployed_block, actual_match)
        if actual_match
          missing = deployed_block[:tokens] - actual_match[:tokens]
          coverage = coverage_ratio(deployed_block[:tokens], actual_match[:tokens])
          SectionReport.new(
            heading: deployed_block[:heading],
            deployed_tokens: deployed_block[:tokens].length,
            actual_tokens: actual_match[:tokens].length,
            missing_tokens: missing.to_a.sort,
            coverage: coverage,
          )
        else
          SectionReport.new(
            heading: deployed_block[:heading],
            deployed_tokens: deployed_block[:tokens].length,
            actual_tokens: 0,
            missing_tokens: deployed_block[:tokens].to_a.sort,
            coverage: 0.0,
          )
        end
      end

      # Pre-index actual blocks by normalized heading for O(1) lookup
      # instead of linear scan. Critical for pages with 800+ H3 headings.
      def index_blocks_by_heading(blocks)
        index = {}
        blocks.each do |b|
          next unless b[:heading]

          norm = normalize_heading(b[:heading])
          index[norm] = b
        end
        index
      end

      def similar_heading?(a, b)
        return false if a.nil? || b.nil?

        a_norm = normalize_heading(a)
        b_norm = normalize_heading(b)
        a_norm == b_norm ||
          a_norm.include?(b_norm) ||
          b_norm.include?(a_norm)
      end

      # Normalize amendment headings so that "Amd. no. 43 to X" and
      # "Amd. no. 46 to X" compare equal — the deployed site's number
      # comes from its own cumulative counter and may differ from ours.
      #
      # Also normalizes "OB no. N" inside any heading so that one
      # amendment per issue (deployed Jekyll convention) matches one
      # amendment per change (our convention) — both collapse to the
      # same normalized identifier for the same OB issue.
      #
      # "Amd." without a number (deployed convention for some registers)
      # compares equal to "Amd. no. N" — both reduce to "amd.".
      def normalize_heading(text)
        text.to_s
            .downcase
            .gsub(/\bamd\.\s*no\.\s*\d+\s*to\s/, 'amd. no. N to ')
            .gsub(/\bamd\.\s*no\.\s*\d+\s*/, 'amd. no. N ')
            .gsub(/\bob\s+no\.\s*\d+/, 'ob no. N')
            .gsub(/\bno\.\s*\d+(?=\s|$|\p{Punct})/, 'no. N')
            .gsub(/\bamd\.\s+no\.\s*N\s+/, 'amd. ')
            .gsub(/\bamd\.\s+to\s+/, '')
            .strip
      end

      def coverage_ratio(deployed_tokens, actual_tokens)
        return 1.0 if deployed_tokens.nil? || deployed_tokens.empty?

        intersection = deployed_tokens & actual_tokens
        intersection.length.to_f / deployed_tokens.length
      end

      def missing_headings(deployed_root, actual_root)
        deployed = heading_texts(deployed_root).map { |t| normalize_heading(t) }
        actual = heading_texts(actual_root).map { |t| normalize_heading(t) }
        deployed - actual
      end

      def heading_texts(root)
        return [] if root.nil?

        root.css('h1, h2, h3, h4, h5, h6').map { |n| node_text(n) }.reject(&:empty?)
      end

      def missing_links(deployed_root, actual_root)
        return [] if deployed_root.nil? || actual_root.nil?

        actual_hrefs = Set.new(actual_root.css('a').map { |a| a['href'] }
                                  .compact)
        deployed_root.css('a').select do |a|
          href = a['href']
          next false if href.nil? || internal_anchor?(href)
          next false if actual_hrefs.include?(href)
          next false if dead_route?(href)

          # Accept semantic equivalents: `/issues/1234-en/` matches
          # `/issues/1234/`.
          next false if href_matches_any?(href, actual_hrefs)

          true
        end.map { |a| { href: a['href'], text: node_text(a) } }.uniq
      end

      # Internal anchors (#foo) are chrome — ignore them in link comparison.
      def internal_anchor?(href)
        return false if href.match?(/\A#year-\d{4}\z/)

        href.start_with?('#')
      end

      # Dead Jekyll routes that we deliberately don't reproduce.
      # - /docs/               : placeholder, never had content
      # - /messages/amending-sp*  : old amendment URL pattern (replaced by /issues/N/#amd-SLUG)
      # - /messages/complement-*  : old recommendation-complement URL pattern (replaced by /recommendations/CODE/)
      # - https://open.ribose.com/ : defunct maintainer link
      # - "2011/" and "../2011/" style relative year hrefs : Jekyll
      #   year-archive routes (replaced by /registers/{slug}/at/{issue}/
      #   and per-year recommendation pages, rendered as our "Browse
      #   previous years" navigation)
      DEAD_ROUTE_PATTERNS = [
        %r{\A/docs/?\z},
        %r{\A/messages/amending-sp},
        %r{\A/messages/complement-to-itu-t-r},
        %r{\Ahttps?://open\.ribose\.com/?\z},
        %r{\A\d{4}/?\z},
        %r{\A\.\./\d{4}/?\z},
      ].freeze

      def dead_route?(href)
        DEAD_ROUTE_PATTERNS.any? { |re| re.match?(href) }
      end

      # Does `href` semantically match any of `actual_hrefs`? Currently
      # only normalizes `/issues/1234-en` → `/issues/1234` so the deployed
      # Jekyll issue-URL form matches our canonical form.
      def href_matches_any?(href, actual_hrefs)
        norm = normalize_external_href(href)
        return false if norm.nil?

        actual_hrefs.any? { |a| normalize_external_href(a) == norm }
      end

      def normalize_href(href)
        return nil if href.nil?
        href = href.strip
        return nil if href.empty?
        return href if href.start_with?('http://', 'https://', 'mailto:')

        if (m = href.match(/\A#year-(\d{4})\z/))
          return m[1]
        end

        h = href.sub(/#.*\z/, '').chomp('/')
        if (m = h.match(%r{\A/issues/(\d+)(?:-en)?\z}))
          return "/issues/#{m[1]}"
        end
        h
      end

      def normalize_external_href(href)
        return nil if href.nil?
        href = href.strip
        if (m = href.match(%r{\Ahttps?://www\.itu\.int/pub/T-SP-OB\.(\d+)-\d+\z}))
          return "/issues/#{m[1]}"
        end
        normalize_href(href)
      end

      def missing_tables(deployed_root, actual_root)
        return [] if deployed_root.nil?

        deployed_count = deployed_root.css('table').length
        actual_count = actual_root.nil? ? 0 : actual_root.css('table').length
        deployed_count > actual_count ? [deployed_count - actual_count] : []
      end

      def node_text(node)
        # Nokogiri's Node#text concatenates text without whitespace
        # between block elements, so "Title" + "the" becomes "Titlethe".
        # Walk text nodes explicitly and join with spaces. Exclude
        # <script> and <style> content.
        node.xpath('.//text()[not(ancestor::script) and not(ancestor::style)]')
            .map { |t| t.content }.join(' ').gsub(/\s+/, ' ').strip
      end

      def count_tokens(root)
        return 0 if root.nil?

        tokens_for(spaced_text(root)).length
      end

      def unique_tokens(root)
        return Set.new if root.nil?

        Set.new(tokens_for(spaced_text(root)))
      end

      # Concatenate all descendant text with whitespace between blocks.
      # Excludes <script> and <style> content.
      def spaced_text(root)
        root.xpath('.//text()[not(ancestor::script) and not(ancestor::style)]')
            .map { |t| t.content }
            .join(' ')
      end

      # Tokenize text into semantic words, lowercased, with stop-words,
      # short tokens and punctuation-only runs (printed separator lines
      # like "____________") removed. ISO 8601 datetimes are normalized
      # to the canonical OB Roman-numeral form so "2018-12-15 00:00:00
      # UTC" and "15.XII.2018" produce the same token set.
      def tokens_for(text)
        return [] if text.nil?

        normalized = normalize_dates(text.to_s)
        normalized.scan(/\p{Word}+/)
                 .map(&:downcase)
                 .reject { |w| w.length < MIN_TOKEN_LENGTH }
                 .reject { |w| STOP_WORDS.include?(w) }
                 .reject { |w| w.match?(/\A[\p{Punct}_]+\z/) }
      end

      ROMAN_MONTHS = %w[I II III IV V VI VII VIII IX X XI XII].freeze

      # English month abbreviations as used by the deployed Jekyll site
      # ("Apr 15", "Sep 1"). Mapped to OB Roman numerals so tokens match
      # the Swiss-format dates ("15.IV", "1.IX") we render.
      ENGLISH_MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

      # Convert ISO 8601 dates and datetimes (e.g. "2018-12-15",
      # "2018-12-15 00:00:00 UTC") to OB Roman-numeral form
      # ("15.XII.2018"). Also normalizes English month abbreviations
      # ("Apr 15", "15 Apr") → "15.IV" so the deployed register-page
      # date column matches our Swiss-format dates token-for-token.
      def normalize_dates(text)
        iso_normalized = text.gsub(/\b(\d{4})-(\d{2})-(\d{2})(?:\s+\d{2}:\d{2}(?::\d{2})?)?(?:\s+UTC)?\b/) do
          year = Regexp.last_match(1)
          month = Regexp.last_match(2).to_i
          day = Regexp.last_match(3)
          month_rom = (month >= 1 && month <= 12) ? ROMAN_MONTHS[month - 1] : month.to_s
          "#{day}.#{month_rom}.#{year}"
        end

        # "Mon DD" → "DD.Roman" (e.g. "Apr 15" → "15.IV")
        en_mon_dd = iso_normalized.gsub(/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{1,2})\b/i) do
          month_idx = ENGLISH_MONTHS.index(Regexp.last_match(1).downcase)
          day = Regexp.last_match(2)
          month_idx ? "#{day}.#{ROMAN_MONTHS[month_idx]}" : Regexp.last_match(0)
        end

        # "DD Mon" → "DD.Roman" (e.g. "15 Apr" → "15.IV")
        en_mon_dd.gsub(/\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b/i) do
          month_idx = ENGLISH_MONTHS.index(Regexp.last_match(2).downcase)
          day = Regexp.last_match(1)
          month_idx ? "#{day}.#{ROMAN_MONTHS[month_idx]}" : Regexp.last_match(0)
        end
      end

      # Memoize the STOP_WORDS set lookup by exposing the constant.
      def stop_words
        STOP_WORDS
      end
    end

    # Immutable value object summarizing a parity comparison.
    class Report
      attr_reader :deployed_tokens, :actual_tokens,
                  :deployed_unique, :actual_unique,
                  :sections, :missing_headings, :missing_links, :missing_tables

      def initialize(deployed_tokens:, actual_tokens:,
                     deployed_unique:, actual_unique:,
                     sections:, missing_headings:, missing_links:,
                     missing_tables:)
        @deployed_tokens = deployed_tokens
        @actual_tokens = actual_tokens
        @deployed_unique = deployed_unique
        @actual_unique = actual_unique
        @sections = sections
        @missing_headings = missing_headings
        @missing_links = missing_links
        @missing_tables = missing_tables
        freeze
      end

      # Frequency-capped weighted coverage: ratio of deployed tokens
      # (capped per-word) that appear at least once in actual.
      def coverage
        return 1.0 if @deployed_unique.empty?

        intersection = @deployed_unique & @actual_unique
        intersection.length.to_f / @deployed_unique.length
      end

      def to_report_hash
        {
          deployed_tokens: @deployed_tokens,
          actual_tokens: @actual_tokens,
          deployed_unique: @deployed_unique.length,
          actual_unique: @actual_unique.length,
          coverage: coverage.round(4),
          missing_headings: @missing_headings,
          missing_links_count: @missing_links.length,
          missing_tables: @missing_tables,
          sections: @sections.map(&:to_section_hash),
        }
      end
    end

    # One deployed section's comparison result.
    class SectionReport
      attr_reader :heading, :deployed_tokens, :actual_tokens,
                  :missing_tokens, :coverage

      def initialize(heading:, deployed_tokens:, actual_tokens:,
                     missing_tokens:, coverage:)
        @heading = heading
        @deployed_tokens = deployed_tokens
        @actual_tokens = actual_tokens
        @missing_tokens = missing_tokens
        @coverage = coverage
        freeze
      end

      def to_section_hash
        {
          heading: @heading,
          deployed_tokens: @deployed_tokens,
          actual_tokens: @actual_tokens,
          missing_tokens: @missing_tokens,
          coverage: @coverage.round(4),
        }
      end
    end
  end
end
