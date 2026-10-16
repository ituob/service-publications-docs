# frozen_string_literal: true

module Ituob
  module Catalogs
    # Catalog of OB Registers — named datasets mandated by an ITU-T
    # Recommendation.
    #
    # Canonical data lives in +catalogs/registers.yaml+. A Register is
    # distinct from a Publication (the ITU-T Rec document) and from a
    # Service Publication (a printable snapshot of the register at a
    # point in time).
    #
    # Inherits the lazy-load + index-by-key pattern from +YamlCatalog+.
    # The slug index is declared as a secondary lookup.
    module Registers
      Classification = Struct.new(:name) do
        def structured? = name == :structured
        def textual? = name == :textual
      end

      STRUCTURED = Classification.new(:structured)
      TEXTUAL = Classification.new(:textual)

      Entry = Struct.new(
        :register_id, :slug, :recommendation, :title, :key_field,
        :classification, :parser_class_name, :renderer,
        :seed_issue, :seed_path, :external,
        keyword_init: true,
      ) do
        def structured? = classification&.structured?
        def textual? = classification&.textual?
        def external? = external == true
        def title_en = title&.dig('en') || ''
      end

      class << self
        include YamlCatalog

        # -- YamlCatalog hooks ----------------------------------------

        def yaml_key
          'registers'
        end

        def primary_key
          :register_id
        end

        def default_path
          File.expand_path('../../../../catalogs/registers.yaml', __dir__)
        end

        def declare_indices
          index_by :slug
        end

        def build_entry(hash)
          classification = case hash['classification']
                           when 'structured' then STRUCTURED
                           when 'textual' then TEXTUAL
                           end
          Entry.new(
            register_id: hash['register_id'],
            slug: hash['slug'],
            recommendation: hash['recommendation'],
            title: hash['title'],
            key_field: hash['key_field'],
            classification: classification,
            parser_class_name: hash['parser_class'],
            renderer: hash['renderer'],
            seed_issue: hash['seed_issue'],
            seed_path: hash['seed_path'],
            external: hash['external'],
          )
        end

        # -- Convenience wrappers (back-compat with the pre-refactor API) --

        def all_register_ids
          all_keys
        end

        def all_slugs
          ensure_loaded!
          indices[:slug].keys
        end

        def find_by_slug(slug)
          find_by(:slug, slug)
        end

        def for_recommendation(code)
          all.select { |e| e.recommendation == code.to_s }
        end

        # Backwards-compatible slug derivation: if the publication_id
        # is in the legacy catalog, return its slug; otherwise derive.
        def slug_for(register_id)
          entry = find(register_id)
          return entry.slug if entry

          register_id.to_s.downcase.gsub(/\./, '-').gsub(/[^a-z0-9-]+/, '-')
                       .gsub(/-{2,}/, '-').gsub(/\A-|-\z/, '')
        end

        def parser_class_for(register_id)
          entry = find(register_id)
          return nil unless entry&.parser_class_name

          entry.parser_class_name.split('::').reduce(Object) do |mod, name|
            mod.const_get(name)
          end
        end

        def each_entry(&block)
          each(&block)
        end
      end
    end
  end
end
