require 'lutaml/model'
require_relative 'general_message'
require_relative 'helpers'

module Ituob
  module Models
    class GeneralCustom < GeneralMessage
      attribute :text, :string

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'custom'
        msg.type = data['type']

        msg.text = Ituob::Helpers.dump_doc_full(data)
        msg 
      end
    end
  end
end
