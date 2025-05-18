require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'
require 'prosereflect'

module Ituob
  module Models
    class GeneralIptn < GeneralMessage
      # /1114-E.164D-Note-PQ/schema-data.yaml ? 
      
      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string
      attribute :formerly, :string
      attribute :notes, :string


      key_value do
        map 'type', to: :type
        map 'applicant', to: :applicant
        map 'network', to: :network
        map 'cc_ic', to: :cc_ic
        map 'status', to: :status
        map 'formerly', to: :formerly
        map 'notes', to: :notes
      end

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'iptn'
        msg.type = data['type']

        notes = []

        doc = Prosereflect::Parser.parse_document(data)
        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each do |c|
          next unless c
          if c[0].is_a?(String)
            notes << c[0]
          elsif c[0].is_a?(Array)
            msg.applicant = c[1][0][0]
            msg.network = c[1][1][0]
            msg.cc_ic = c[1][2][0]
          end
        end

        msg.notes = notes.join('\n').strip
        msg
      end

    end

  end
end
