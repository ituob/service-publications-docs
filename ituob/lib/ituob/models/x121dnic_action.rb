# frozen_string_literal: true

module Ituob
  module Models
    # One change group of an X.121 DNIC amendment.
    #
    # +position+ is the printed locator ("P 206 6", "P21 240 2", or a
    # DNIC list "206 1, 206 2, ..."), +country+ the printed country
    # name, +caption+ the printed table header wording ("Name of
    # network to which a DNIC is allocated/withdrawn" -- it varies by
    # action type), +description+ the verbatim change line and
    # +entries+ the parsed table rows.
    class X121DNICAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :country, :string
      attribute :caption, :string
      attribute :description, :string
      attribute :entries, X121DNICEntry, collection: true
    end
  end
end
