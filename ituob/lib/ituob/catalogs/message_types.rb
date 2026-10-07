# frozen_string_literal: true

require 'yaml'

module Ituob
  module Catalogs
    # Catalog of OB general-message types, loaded from canonical YAML.
    module MessageTypes
      @loaded = false

      class << self
        attr_reader :structured_types, :textual_types, :metadata

        def load!(path: nil)
          path ||= default_path
          data = Ituob::Support::Yaml.safe_load_file(path)
          @structured_types = (data || {}).fetch('structured', []).freeze
          @textual_types = (data || {}).fetch('textual', []).freeze
          @untyped = (data || {}).fetch('untyped', 'no_type')
          @metadata = (data || {}).fetch('metadata', {})
          @loaded = true
          self
        end

        def ensure_loaded!
          load! unless @loaded
        end

        def untyped
          ensure_loaded!
          @untyped
        end


        def category(type)
          ensure_loaded!
          type_str = type.to_s
          return :structured if @structured_types.include?(type_str)
          return :textual if @textual_types.include?(type_str)

          nil
        end

        def known?(type)
          ensure_loaded!
          t = type.to_s
          @structured_types.include?(t) || @textual_types.include?(t)
        end

        def structured?(type)
          ensure_loaded!
          @structured_types.include?(type.to_s)
        end

        def textual?(type)
          ensure_loaded!
          @textual_types.include?(type.to_s)
        end

        def relative_path_for(type, sequence: nil)
          case category(type)
          when :structured then "general/#{type}.yaml"
          when :textual    then "#{type}/#{format('%03d', sequence || 1)}.yaml"
          else
            raise ArgumentError, "unknown general message type: #{type.inspect}"
          end
        end

        def all_types
          ensure_loaded!
          @structured_types + @textual_types
        end

        def reset!
          @loaded = false
          @structured_types = nil
          @textual_types = nil
          @metadata = nil
        end

        private

        def default_path
          File.expand_path('../../../../catalogs/message_types.yaml', __dir__)
        end
      end
    end
  end
end

require 'set'
