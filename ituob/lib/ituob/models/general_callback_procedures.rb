require 'lutaml/model'
require_relative 'general_message'

module Ituob
  module Models
    class GeneralCallbackProcedures < GeneralMessage
      def self.parse(data)
        return nil
        # no attributes...
      end
    end
  end
end
