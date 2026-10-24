# frozen_string_literal: true

require 'lutaml/model'


module Ituob
  module Models
    class GeneralServiceRestrictions < GeneralMessage
      attribute :ob_issue_no, :string
      attribute :items, GeneralServiceRestriction, collection: true

      key_value do
        map 'ob_issue_no', to: :ob_issue_no
        map 'items', to: :items
      end
    end
  end
end
