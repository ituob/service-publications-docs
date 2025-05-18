require 'lutaml/model'
require_relative 'general_message'


module Ituob
  module Models
    class GeneralSanc < ::Lutaml::Model::Serializable
      attribute :country, :string
      attribute :sanc, :string
    end

    class GeneralSancs < GeneralMessage
      attribute :items, GeneralSanc, collection: true
      attribute :notes, :string
      
      key_value do
        map 'type', to: :type
        map 'items', to: :items
      end

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'sanc'
        msg.type = data['type']
        msg.items = []

        notes = []

        doc = Prosereflect::Parser.parse_document(data)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each do |c|
          next unless c
          if c[0].is_a?(String)
            notes << c[0]
          elsif c[0].is_a?(Array)
            c.each do |r|
              next if r.empty? || r.length < 2 || r[0][0].match(/^Country/) || r[1][0].match(/^Country/)
              item = GeneralSanc.new
              item.country = r[0][0]
              item.sanc = r[1][0]
              msg.items << item 
            end
          end
        end

        msg.notes = notes.join('\n').strip
        msg
      end

    end

  end
end
