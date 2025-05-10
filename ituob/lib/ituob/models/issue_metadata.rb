# frozen_string_literal: true

require 'lutaml/model'
require_relative 'multilingual_string'

# id: 1000
# publication_date: 2012-03-15T00:00:00.000Z
# cutoff_date: 2012-03-03T00:00:00.000Z
# issn: 1564-5223
# languages:
#   en: true
# authors:
#   - address: |-
#       Place des Nations CH-1211
#       Genève 20 (Switzerland)
#     contacts:
#       - type: phone
#         data: +41 22 730 5111
#       - type: email
#         data: itumail@itu.int
#         recommended: true
#   - name: Standardization Bureau (TSB)
#     contacts:
#       - type: phone
#         data: +41 22 730 5211
#         recommended: true
#       - type: fax
#         data: +41 22 730 5853
#         recommended: true
#       - type: email
#         data: tsbmail@itu.int
#         recommended: true
#       - type: email
#         data: tsbtson@itu.int
#         recommended: true
#   - name: Radiocommunication Bureau (BR)
#     contacts:
#       - type: phone
#         data: +41 22 730 5560
#         recommended: true
#       - type: fax
#         data: +41 22 730 5785
#         recommended: true
#       - type: email
#         data: brmail@itu.int
#         recommended: true

module Ituob
  module Models
    class IssueContact < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :data, :string
      attribute :recommended, :boolean
    end

    class IssueAuthor < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :address, :string
      attribute :contacts, IssueContact, collection: true
      attribute :recommended, :boolean
    end

        # Base class for all dataset entries
    class IssueMetadata < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :publication_date, :date
      attribute :cutoff_date, :date
      attribute :issn, :string
      attribute :languages, MultilingualString
      attribute :authors, IssueAuthor, collection: true
    end

  end
end
