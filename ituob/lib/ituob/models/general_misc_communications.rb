require 'lutaml/model'
require_relative 'general_message'

module Ituob
  module Models
    class GeneralMiscCommunications < GeneralMessage
      attribute :text, :string

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'misc_communications'
        msg.type = data['type']

        msg.text = Ituob::Helpers.dump_doc_full(data)
        msg 
      end
    end
  end
end
