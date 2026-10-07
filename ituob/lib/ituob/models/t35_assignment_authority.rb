# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    class T35AssignmentAuthority < Lutaml::Model::Serializable
      attribute :terminal_type, :string
      attribute :contact_name, :string
      attribute :organization, :string
      attribute :department, :string
      attribute :address, :string
      attribute :telephone, :string
      attribute :fax, :string
      attribute :email, :string
      attribute :related_links, :string, collection: true
    end
  end
end
