require 'lutaml/model'
require_relative 'general_message'


module Ituob
  module Models
    class GeneralServiceRestrictions < GeneralMessage
      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'running_annexes'

        # they're all empty 
        from_hash(data)
      end
    end
  end
end
