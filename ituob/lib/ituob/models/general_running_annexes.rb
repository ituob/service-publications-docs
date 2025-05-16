require 'lutaml/model'
require_relative 'general_message'

module Ituob
  module Models
    class GeneralRunningAnnexes < GeneralMessage
      attribute :extra_links, :string, collection: true

      def self.parse(data)
        return unless data.is_a?(Hash) && data['type'] == 'running_annexes'

        from_hash(data)
      end
    end
  end
end
