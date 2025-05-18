require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class GeneralIpns < GeneralMessage
      attribute :network, :string
      attribute :mcc_mnc, :string
      attribute :notes, :string

      key_value do
        map 'type', to: :type
        map 'network', to: :network
        map 'mcc_mnc', to: :mcc_mnc
        map 'notes', to: :notes
      end

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'ipns'
        msg.type = data['type']

        notes = []

        doc = Prosereflect::Parser.parse_document(data)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each do |c|
          next unless c
          if c[0].is_a?(String)
            notes << c[0]
          elsif c[0].is_a?(Array)
            msg.network = c[1][0][0]
            msg.mcc_mnc = c[1][1][0]
          end
        end

        msg.notes = notes.join('\n').strip
        msg
      end

    end

  end
end
