# frozen_string_literal: true
require 'lutaml/model'

module Ituob
  module Models
    class GeneralApprovedRecommendations < GeneralMessage
      attribute :items, GeneralApprovedRecommendation, collection: true
      attribute :by, :string
      attribute :procedures, :string
attribute :ob_issue_no, :string
attribute :payload, :hash

      key_value do
        map 'items', to: :items
        map 'type', to: :type
        map 'by', to: :by
        map 'procedures', to: :procedures
map 'ob_issue_no', to: :ob_issue_no
map 'payload', to: :payload
      end

      # Editor-era `items` is a {recommendation => date} mapping; the
      # model holds a list. The date is kept as stored (a timestamp
      # stays that timestamp, free text such as "2015" stays text).
      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'approved_recommendations'

        items = (data['items'] || {}).map do |key, value|
          { 'recommendation' => key.gsub(/[[:space:]]/, ' ').strip, 'approved_date' => value }
        end

        from_hash(data.merge('items' => items))
      end

    end

  end
end
