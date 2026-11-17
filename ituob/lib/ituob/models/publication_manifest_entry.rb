# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Models
    # One rendered service-publication PDF (publication x language). Field
    # names are the contract read by ituob.github.io src/lib/publications.ts;
    # see docs/pdf/manifest.adoc. +recommendation+ is extra to that contract
    # (the site ignores unknown keys) and keeps the grouping key that +standard+
    # (the directory token, for example E.212B) cannot give.
    class PublicationManifestEntry < Lutaml::Model::Serializable
      STATUSES = %w[candidate itu-adopted].freeze

      attribute :standard, :string
      attribute :recommendation, :string
      attribute :title, :string
      attribute :edition_year, :integer
      attribute :language, :string
      attribute :as_of_issue, :integer
      attribute :sha256, :string
      attribute :status, :string, values: STATUSES
      attribute :register_slugs, :string, collection: true, initialize_empty: true
      attribute :path, :string

      key_value do
        map 'standard', to: :standard
        map 'recommendation', to: :recommendation
        map 'title', to: :title
        map 'edition_year', to: :edition_year
        map 'language', to: :language
        map 'as_of_issue', to: :as_of_issue
        map 'sha256', to: :sha256
        map 'status', to: :status
        map 'register_slugs', to: :register_slugs, render_empty: true
        map 'path', to: :path
      end
    end
  end
end
