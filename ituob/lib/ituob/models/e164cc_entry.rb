# frozen_string_literal: true


module Ituob
  module Models
    class E164CCEntry < Entry
      DATASET_CODE = 'E164_CC'

      attribute :applicant, :string
      attribute :network, :string
      attribute :cc_ic, :string
      attribute :status, :string
      attribute :formerly, :string
      attribute :action_date, :string
      attribute :reclamation_date, :string
    end
  end
end
