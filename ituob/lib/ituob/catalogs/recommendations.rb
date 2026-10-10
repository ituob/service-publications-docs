# frozen_string_literal: true

module Ituob
  module Catalogs
    # Catalog of ITU-T Recommendations that create OB registers.
    #
    # Canonical data lives in +catalogs/recommendations.yaml+.
    # Inherits the lazy-load + index-by-key pattern from +YamlCatalog+.
    module Recommendations
      Entry = Struct.new(
        :code, :bureau, :title, :version, :document_path, :url, :registers,
        keyword_init: true,
      ) do
        def title_en = title&.dig('en') || ''
      end

      class << self
        include YamlCatalog

        # -- YamlCatalog hooks ----------------------------------------

        def yaml_key
          'recommendations'
        end

        def primary_key
          :code
        end

        def default_path
          File.expand_path('../../../../catalogs/recommendations.yaml', __dir__)
        end

        def build_entry(hash)
          Entry.new(
            code: hash['code'],
            bureau: hash['bureau'],
            title: hash['title'],
            version: hash['version'],
            document_path: hash['document_path'],
            url: hash['url'],
            registers: hash['registers'] || [],
          )
        end
      end
    end
  end
end
