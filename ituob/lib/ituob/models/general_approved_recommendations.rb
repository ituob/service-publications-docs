require 'lutaml/model'
require_relative 'general_message'

module Ituob
  module Models
    class GeneralApprovedRecommendation < ::Lutaml::Model::Serializable
      attribute :recommendation, :string
      attribute :approved_date, :date
    end

    class GeneralApprovedRecommendations < GeneralMessage
      attribute :items, GeneralApprovedRecommendation, collection: true
      attribute :by, :string
      attribute :procedures, :string

      key_value do
        map 'items', to: :items
        map 'type', to: :type
        map 'by', to: :by
        map 'procedures', to: :procedures
      end

      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'approved_recommendations'

        # Ensure the 'items' field is an array
        items = data['items'].inject([]) do |acc, (key, value)|
          acc << {
            recommendation: key.gsub(/[[:space:]]/, ' ').strip,
            approved_date: value,
          }
          acc
        end
        data['items'] = items

        from_hash(data)
      end

    end

  end
end
