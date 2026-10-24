# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class GeneralMiscCommunications < GeneralMessage
      attribute :ob_issue_no, :string
      attribute :contents, :hash
      attribute :text, :string

      key_value do
        map 'ob_issue_no', to: :ob_issue_no
        map 'contents', to: :contents
        map 'text', to: :text
      end
    end
  end
end
