# frozen_string_literal: true

module Ituob
  module Domain
    # A single communication dated within a country's telephone service
    # entry. Each communication is a freeform ProseMirror doc.
    class TelephoneServiceCommunication < Struct.new(:date, :contents, keyword_init: true)
      def initialize(*args)
        super
        freeze
      end

      # Plain-text body of the communication (paragraphs joined).
      def body_text
        return '' unless contents.is_a?(Hash)

        parts = []
        walk(contents) do |n|
          next unless n.is_a?(Hash)
          next unless n['type'] == 'text'

          parts << n.fetch('text', '')
        end
        parts.join(' ').strip
      end

      private

      def walk(node, &block)
        case node
        when Hash
          yield node
          node.each_value { |v| walk(v, &block) }
        when Array
          node.each { |v| walk(v, &block) }
        end
      end
    end

    # A country entry in a telephone service message.
    class TelephoneServiceCountry < Struct.new(:name, :phone_code, :contact, keyword_init: true)
      def initialize(*args)
        super
        freeze
      end

      # English name, or empty string.
      def en_name
        localized = name.is_a?(Hash) ? name['en'] : name
        localized.to_s
      end

      # Plain-text contact block.
      def contact_text
        return '' unless contact

        contact.is_a?(Hash) ? contact.fetch('en', contact.to_s) : contact.to_s
      end
    end

    # A complete telephone service entry: a country + its communications.
    class TelephoneServiceEntry
      attr_reader :country, :communications

      def initialize(country:, communications:)
        @country = country
        @communications = Array(communications)
        freeze
      end

      # Build from the raw source message hash.
      def self.from_message_hash(message_hash)
        country_hash = message_hash.fetch('country_name', {})
        phone = message_hash['phone_code']
        contact = message_hash['contact']

        country = TelephoneServiceCountry.new(
          name: country_hash,
          phone_code: phone,
          contact: contact,
        )

        comms = (message_hash['communications'] || []).map do |c|
          TelephoneServiceCommunication.new(date: c['date'], contents: c['contents'])
        end

        new(country: country, communications: comms)
      end
    end
  end
end
