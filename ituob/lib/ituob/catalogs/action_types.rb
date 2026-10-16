# frozen_string_literal: true

require 'yaml'

module Ituob
  module Catalogs
    # Catalog of valid action types, loaded from canonical YAML.
    module ActionTypes
      @loaded = false

      class << self
        attr_reader :all_list, :rep_equivalent_list, :labels_hash

        def load!(path: nil)
          path ||= default_path
          data = Ituob::Support::Yaml.safe_load_file(path)
          @all_list = (data || {}).fetch('all', []).freeze
          @rep_equivalent_list = (data || {}).fetch('rep_equivalent', []).freeze
          @labels_hash = (data || {}).fetch('labels', {})
          @loaded = true
          self
        end

        def ensure_loaded!
          load! unless @loaded
        end

        # Array of all valid action type strings.
        def all
          ensure_loaded!
          @all_list
        end

        # Array of action types semantically equivalent to REP.
        def rep_equivalent
          ensure_loaded!
          @rep_equivalent_list
        end

        # Regex matching any action keyword (optionally with trailing *).
        def keyword_regex
          /\b(ADD|SUP|REP|LIR|MOD|DEL)\b\*?/
        end

        def valid?(value)
          return false unless value.is_a?(String)

          all.include?(value.strip.upcase.sub(/\*+\z/, ''))
        end

        def normalize(value)
          return nil unless value.is_a?(String)

          normalized = value.strip.upcase.sub(/\*+\z/, '')
          all.include?(normalized) ? normalized : nil
        end

        def find_last_in(text)
          return nil unless text.is_a?(String)

          matches = text.upcase.scan(keyword_regex).map(&:first)
          matches.last
        end

        def each_in(text)
          return enum_for(:each_in, text) unless block_given?

          return unless text.is_a?(String)

          text.upcase.scan(keyword_regex).each do |m|
            yield m.first
          end
        end

        def rep_equivalent?(action)
          rep_equivalent.include?(action.to_s.upcase)
        end

        def label_for(action)
          ensure_loaded!
          @labels_hash[action.to_s.upcase] || action.to_s
        end

        def reset!
          @loaded = false
          @all_list = nil
          @rep_equivalent_list = nil
          @labels_hash = nil
        end

        private

        def default_path
          File.expand_path('../../../../catalogs/action_types.yaml', __dir__)
        end
      end
    end
  end
end
