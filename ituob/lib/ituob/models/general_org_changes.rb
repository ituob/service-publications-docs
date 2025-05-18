require 'lutaml/model'
require_relative 'general_message'

module Ituob
  module Models
    class GeneralOrgChanges < GeneralMessage
      attribute :text, :string

      def self.parse(data)
        msg = new 
        return unless data.is_a?(Hash) && data['type'] == 'org_changes'
        msg.type = data['type']

        msg.text = Ituob::Helpers.dump_doc_full(data)
        msg 
      end
    end
  end
end
