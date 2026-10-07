# frozen_string_literal: true

module Ituob
  module Models
    # The centralizing office printed above a List VIII monitoring
    # station block: office name, postal address, contact lines
    # (telephone/telefax/e-mail), remarks.
    class ListVIIICentralizingOffice < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :postal_address, :string
      attribute :contact, :string
      attribute :remarks, :string
    end
  end
end
