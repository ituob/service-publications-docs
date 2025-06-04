require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'

module Ituob
  module Models
    class GeneralTelephoneService < GeneralMessage
      attribute :text, :string
    end

    class GeneralTelephoneServices < GeneralMessage
      attribute :items, GeneralTelephoneService, collection: true

      key_value do
        map 'items', to: :items
        map 'type', to: :type
      end

      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'telephone_service_2'
        svc = new
        svc.items = []

        data['contents'].each do |c1|
          c1['communications'].each do |c2|
            doc = Prosereflect::Parser.parse_document(c2['contents']['en'])
            gts = GeneralTelephoneService.new
            gts.text = Ituob::Helpers.dump_doc(doc).to_json
            svc.items << gts
          end
        end
        
        svc
      end
    end
  end
end
