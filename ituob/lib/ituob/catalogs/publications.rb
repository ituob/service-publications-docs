# frozen_string_literal: true

require 'yaml'

module Ituob
  module Catalogs
    # Legacy facade over the now-preferred {Ituob::Catalogs::Registers}
    # catalog.
    #
    # Historical note: +publications.yaml+ conflated "publication"
    # (the SP document) with "register" (the dataset). The canonical
    # split lives in +catalogs/registers.yaml+ and
    # +catalogs/recommendations.yaml+ (see {Registers} and
    # {Recommendations}).
    #
    # Existing code calling +Publications.slug_for+,
    # +Publications.parser_class_for+, etc. keeps working — this
    # module translates {Registers::Entry} into the legacy
    # {Publications::Entry} shape on demand. New code should call
    # {Registers} directly.
    module Publications
      Classification = Struct.new(:name) do
        def structured? = name == :structured
        def textual? = name == :textual
      end

      STRUCTURED = Classification.new(:structured)
      TEXTUAL = Classification.new(:textual)

      Entry = Struct.new(
        :publication_id, :slug, :classification, :parser_class_name,
        :renderer, :recommendation, :issue_introduced, :external,
        keyword_init: true,
      ) do
        def structured? = classification&.structured?
        def textual? = classification&.textual?
        def external? = external == true
      end

      class << self
        # Translate every Registers::Entry into a legacy Entry on
        # demand. Memoised; refreshes when Registers is reloaded.
        def by_publication_id
          build_index unless @indexed
          @by_publication_id
        end
        alias_method :by_id, :by_publication_id

        def by_slug
          build_index unless @indexed
          @by_slug
        end

        def ensure_loaded!
          build_index unless @indexed
        end

        def load!(**)
          rebuild!
          self
        end

        def reset!
          @indexed = false
          @by_publication_id = nil
          @by_slug = nil
          Registers.reset!
        end

        def slug_for(publication_id)
          Registers.slug_for(publication_id)
        end

        def publication_for(slug)
          entry = Registers.find_by_slug(slug.to_s)
          entry&.register_id
        end

        def classify(publication_id)
          entry = Registers.find(publication_id.to_s)
          return nil unless entry

          entry.structured? ? STRUCTURED : TEXTUAL
        end

        def structured?(publication_id)
          entry = Registers.find(publication_id.to_s)
          entry&.structured?
        end

        def textual?(publication_id)
          entry = Registers.find(publication_id.to_s)
          entry&.textual?
        end

        def known?(publication_id)
          Registers.find(publication_id.to_s) ? true : false
        end

        def each_entry
          return to_enum(__method__) unless block_given?

          Registers.each_entry do |reg_entry|
            yield translate(reg_entry)
          end
        end

        def parser_class_for(publication_id)
          Registers.parser_class_for(publication_id.to_s)
        end

        def entry_for_slug(slug)
          reg_entry = Registers.find_by_slug(slug.to_s)
          translate(reg_entry) if reg_entry
        end

        def all_publication_ids
          Registers.all_register_ids
        end

        def all_slugs
          Registers.all_slugs
        end

        def renderer_for(publication_id)
          entry = Registers.find(publication_id.to_s)
          return entry.renderer if entry&.renderer
          return 'structured-amendment' if entry&.structured?
          return 'text-amendment' if entry&.textual?

          'text-amendment'
        end

        private

        def build_index
          @by_publication_id = {}
          @by_slug = {}
          Registers.each_entry do |reg_entry|
            legacy = translate(reg_entry)
            @by_publication_id[legacy.publication_id] = legacy
            @by_slug[legacy.slug] = legacy
          end
          @indexed = true
        end

        def rebuild!
          Registers.reset!
          Registers.ensure_loaded!
          @indexed = false
          build_index
        end

        def translate(reg_entry)
          classification = reg_entry.structured? ? STRUCTURED : TEXTUAL
          Entry.new(
            publication_id: reg_entry.register_id,
            slug: reg_entry.slug,
            classification: classification,
            parser_class_name: reg_entry.parser_class_name,
            renderer: reg_entry.renderer,
            recommendation: reg_entry.recommendation,
            issue_introduced: reg_entry.seed_issue,
            external: reg_entry.external,
          )
        end
      end
    end
  end
end
