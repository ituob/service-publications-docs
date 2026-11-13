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

      # Editor-era message hash -> instance, for the message types whose
      # payload needs no restructuring (custom, misc_communications,
      # org_changes, service_restrictions, ...). Types that restructure
      # their payload define their own +parse+.
      def self.parse(data)
        return unless data.is_a?(Hash)

        from_hash(data)
      end
    end
  end
end
