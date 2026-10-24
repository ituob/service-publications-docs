# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class GeneralCallbackProcedures < GeneralMessage
      attribute :ob_issue_no, :string

      key_value do
        map 'ob_issue_no', to: :ob_issue_no
      end

      def self.parse(data)
        return nil
        # no attributes...
      end
    end
  end
end
