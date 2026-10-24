# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # File-level envelope for the freeform textual general messages:
    # the ProseMirror document travels in `contents` (untyped Hash).
    class GeneralMessage < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :ob_issue_no, :string
      attribute :contents, :hash

      key_value do
        map 'type', to: :type
        map 'ob_issue_no', to: :ob_issue_no
        map 'contents', to: :contents
      end
    end
  end
end
