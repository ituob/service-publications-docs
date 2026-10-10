# frozen_string_literal: true

# Parent namespace for per-type Ruby renderers.
#
# Each renderer is a class that takes a Domain value object and emits
# a Hash payload suitable for both YAML serialization and Astro
# rendering. The renderer registry maps publication slugs to renderer
# classes — open for extension, closed for modification.
#
# Adding a new renderer:
#   1. Create lib/ituob/renderers/my_renderer.rb
#   2. Subclass Ituob::Renderers::Base
#   3. Register: Ituob::Renderers.register('my-slug', MyRenderer)
#   4. Update catalogs/publications.yaml: renderer: my-slug

module Ituob
  module Renderers
    autoload :Base, 'ituob/renderers/base'

    @registry = {}

    class << self
      attr_reader :registry

      def register(slug, renderer_class)
        @registry[slug.to_s] = renderer_class
      end

      def for(slug)
        @registry[slug.to_s]
      end

      def registered?(slug)
        @registry.key?(slug.to_s)
      end

      def clear!
        @registry.clear
      end
    end
  end
end
