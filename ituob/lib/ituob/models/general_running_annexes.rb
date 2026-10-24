# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class GeneralRunningAnnexes < GeneralMessage
      attribute :ob_issue_no, :string
      attribute :extra_links, :string, collection: true
      attribute :payload, :hash

      key_value do
        map 'ob_issue_no', to: :ob_issue_no
        map 'extra_links', to: :extra_links
        map 'payload', to: :payload
      end

      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'running_annexes'

        from_hash(data)
      end
    end
  end
end
