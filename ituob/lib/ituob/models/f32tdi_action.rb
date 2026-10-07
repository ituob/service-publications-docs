# frozen_string_literal: true

module Ituob
  module Models
    # One P/COL change group of an F.32 TDI amendment.
    #
    # +position+ is the printed locator ("P 27 COL 2"), +description+
    # the verbatim change text ("P 27 Madagascar SUP COL 2 REP
    # Batelco Bsc – Bahrain Telecommunications Company (Bsc), Manama
    # by Unitel"), +action_type+ the per-column keyword (REP) and
    # +entries+ the parsed table rows the change applies to.
    class F32TDIAction < Lutaml::Model::Serializable
      attribute :action_type, :string
      attribute :position, :string
      attribute :description, :string
      attribute :entries, F32TDIEntry, collection: true
    end
  end
end
