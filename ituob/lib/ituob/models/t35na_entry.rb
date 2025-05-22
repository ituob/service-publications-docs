# frozen_string_literal: true

require_relative 'multilingual_string'
require_relative 'entry'

module Ituob
  module Models
    class T35NAEntry < Entry
      DATASET_CODE = 'E164_CC'

      attribute :country, :string
      attribute :administration_name, :string
      attribute :manufactures_htv, :string
      attribute :last_updated, :string
      attribute :assignment_authority, :hash, collection: true
        # organization: string
        # terminal_type: Array<string>
        # contact_name: string
        # department: string
        # address: string
        # telephone: string
        # fax: string
        # email: string
        # related_links: Array<string>
        # last_updated: string
      attribute :note, :string 
    end
  end
end
