# frozen_string_literal: true

module Ituob
  module Models
    # Complete the envelope mapping around LML wire renames and its scalar enum.
    module RegisterChangeMapping
      def self.apply(model, renames)
        model.include(self)
        mapping = proc do
          model.attributes.each_key do |attribute|
            map renames.fetch(attribute, attribute.to_s), to: attribute,
                                                          **RegisterChangeMapping.options(attribute)
          end
        end
        model.key_value(&mapping)
        model.yaml(&mapping)
      end

      def self.options(attribute)
        return { with: { from: :read_action_type, to: :write_action_type } } if attribute == :type

        { render_empty: attribute == :data }
      end

      def read_action_type(model, value)
        model.type = model.class.attributes[:type].type.new(value: value)
      end

      def write_action_type(model, document)
        document['type'] = model.type.value if model.type
      end
    end
  end
end
