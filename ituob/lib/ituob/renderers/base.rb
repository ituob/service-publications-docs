# frozen_string_literal: true

module Ituob
  module Renderers
    # Base interface for all renderers.
    #
    # A renderer takes a domain object (ChangeObject, TextAmendmentContent,
    # TelephoneServiceEntry, etc.) and produces a Hash with:
    #   - `html:` — ready-to-render HTML fragment string
    #   - `meta:` — metadata (column labels, action labels, etc.)
    #   - `entries:` — structured entry data for table rendering
    #
    # Subclasses implement #render.
    class Base
      attr_reader :data, :lang

      def initialize(data, lang: 'en')
        @data = data
        @lang = lang.to_s
      end

      def render
        raise NotImplementedError, "#{self.class}#render not implemented"
      end

      protected

      # Escape HTML entities in a string.
      def escape_html(s)
        return '' unless s.is_a?(String)

        s.gsub(/&/, '&amp;')
         .gsub(/</, '&lt;')
         .gsub(/>/, '&gt;')
         .gsub(/"/, '&quot;')
         .gsub(/'/, '&#39;')
      end

      # Pick a localized value from a Hash, preferring @lang then 'en'.
      def pick_localized(hash)
        return '' unless hash.is_a?(Hash)

        hash[@lang] || hash['en'] || hash.values.first || ''
      end
    end
  end
end
