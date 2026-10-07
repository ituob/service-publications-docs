# frozen_string_literal: true

module Ituob
  module Parity
    # URL mapping from deployed Jekyll permalinks to Astro URLs.
    #
    # Deployed Jekyll uses URLs like:
    #   /issues/1234-en/    (with -en language suffix and trailing slash)
    #   /issues/1234-en     (without trailing slash — Jekyll 301-redirects)
    #   /messages/complement-to-itu-t-r E.118/   (with literal spaces)
    #   /messages/amending-sp E212_MNC (date)/   (with parens)
    #
    # Astro uses canonical /issues/1234/, /recommendations/E.118/,
    # /registers/{slug}/, etc.
    #
    # This module centralizes the mapping so both the audit script and
    # its spec can use the same logic.
    module UrlMap
      # Map a deployed register ID to its Astro slug. Pure data.
      REGISTER_SLUGS = {
        'E118_IIN' => 'e118-iin', 'DP' => 'dp', 'E164_ACN' => 'e164-acn',
        'E164_CC' => 'e164-cc', 'E212_MNC' => 'e212-mnc', 'E212_ICC' => 'e212-icc',
        'E218_TRCC' => 'e218-trcc', 'F1' => 'f1', 'F32_TDI' => 'f32-tdi',
        'BUREAUFAX' => 'bureaufax', 'F400_ADMD' => 'f400-admd',
        'M1400_ICC' => 'm1400-icc', 'Q708_ISPC' => 'q708-ispc',
        'Q708_SANC' => 'q708-sanc', 'T35_NA' => 't35-na', 'T35_CC' => 't35-cc',
        'X121_DNIC' => 'x121-dnic', 'RR.25.1' => 'rr251', 'NNP' => 'nnp',
        'List of Coast Stations and Special Service Stations' => 'coast-stations',
        'R_SP_LM.V' => 'list-v', 'R_SP_LN.VIII' => 'list-viii',
      }.freeze

      # Pattern → mapper. Mapper returns either a String (the local URL)
      # or nil (link intentionally dropped).
      MAPPERS = {
        # Issues: /issues/1234-en[/...] → /issues/1234/...
        # Accepts with or without trailing slash, with any language suffix.
        %r{\A/issues/(\d+)(?:-[a-z]{2})?/?\z} => ->(m) { "/issues/#{m[1]}/" },
        %r{\A/issues/(\d+)(?:-[a-z]{2})?/(.+)\z} => ->(m) { "/issues/#{m[1]}/#{m[2]}" },

        # Complement recommendations
        %r{\A/messages/complement-to-itu-t-r ([^/]+)/?\z} => ->(m) { "/recommendations/#{m[1]}/" },

        # Amending-sp register pages
        %r{\A/messages/amending-sp ([^/(]+)(?: \([^)]+\))?/?\z} => ->(m) {
          slug = REGISTER_SLUGS[m[1]]
          slug ? "/registers/#{slug}/" : nil
        },

        # Running annexes index — Astro has /types/running_annexes/
        %r{\A/messages/running_annexes/?\z} => ->(_) { '/types/running_annexes/' },

        # Static asset links — Astro doesn't mirror these
        %r{\A/assets/} => nil,

        # Editor-only docs on deployed site
        %r{\A/_app_help/?} => nil,
        %r{\A/docs/?\z} => ->(_) { '/about/' },
      }.freeze

      # Map a deployed href to its local equivalent, or return nil if
      # the link is intentionally dropped (no Astro equivalent).
      #
      # Strips leading/trailing whitespace and collapses internal
      # newlines to single spaces (Jekyll templates wrap hrefs across
      # lines). Internal spaces are preserved because some Jekyll URLs
      # contain them literally (e.g. "/messages/amending-sp E212_MNC
      # (2018-12-01)/").
      def self.map(href)
        return nil if href.nil?

        href = href.strip.gsub(/\s+/, ' ')
        return nil if href.empty?

        # Relative numeric paths: ../1234/ or 1234/ — usually issue
        # links from Jekyll year-subdirectory pages. 4-digit numbers
        # in 1990..2100 are year links (Astro collapses year subpages).
        if href.match?(%r{\A(?:\.\./)*\d+/?\z})
          id = href.match(%r{\A(?:\.\./)*(\d+)}).captures.first.to_i
          return nil if id >= 1990 && id <= 2100

          return "/issues/#{id}/"
        end

        MAPPERS.each do |pattern, mapper|
          if (match = href.match(pattern))
            return mapper ? mapper.call(match) : nil
          end
        end

        return nil if href.start_with?('#', 'mailto:', 'http://', 'https://', '/assets/')

        return '/' if href == '/'

        href
      end
    end
  end
end
