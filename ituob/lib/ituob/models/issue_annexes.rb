# frozen_string_literal: true

require 'yaml'
require 'lutaml/model'

module Ituob
  module Models
    # The publications annexed to one issue: ob-issues/<n>/annexes.yaml.
    #
    # Wire shape: a mapping of publication id to the annexed position,
    #
    #   Q708_ISPC:
    #     position_on: 2012-03-15T00:00:00.000Z   # a timestamp or a date
    #     datasets: {...}                         # optional, kept as stored
    #   F1_IPTS:                                  # annexed, position unknown
    #
    # lutaml-model has no mapping whose keys are data, so the model is the
    # list of AnnexedPosition and this class owns the transposition. The
    # transposition is exact: map order, nil, timestamp-vs-date and datasets
    # are all kept as stored. An entry with neither position nor datasets is
    # written as null (the only spelling the corpus uses for it). Any other
    # key inside an entry raises, so a malformed file cannot load silently.
    class IssueAnnexes < Lutaml::Model::Serializable
      ENTRY_KEYS = %w[position_on datasets].freeze
      TYPE_TAG = '__type__'

      attribute :positions, AnnexedPosition, collection: true

      def self.from_hash(hash, *_args, **_options)
        raise ArgumentError, 'annexes must be a mapping of publication id to position' unless hash.is_a?(Hash)

        # The LML instance adapter tags a parsed instance with __type__;
        # that tag is not a publication id.
        entries = hash.reject { |id, _| id.to_s == TYPE_TAG }
        new(positions: entries.map { |id, entry| position_from(id.to_s, entry) })
      end

      def self.from_yaml(yaml, *_args, **options)
        data = YAML.safe_load(yaml, permitted_classes: options.fetch(:permitted_classes, [Date, Time]), aliases: true)
        from_hash(data.nil? ? {} : data)
      end

      def self.position_from(id, entry)
        return AnnexedPosition.new(publication_id: id) if entry.nil?
        raise ArgumentError, "#{id}: position must be a mapping or null" unless entry.is_a?(Hash)

        unknown = entry.keys.map(&:to_s) - ENTRY_KEYS
        raise ArgumentError, "#{id}: unknown annex keys #{unknown.sort.inspect}" unless unknown.empty?

        AnnexedPosition.new(publication_id: id, position_on: entry['position_on'], datasets: entry['datasets'])
      end
      private_class_method :position_from

      def to_hash(*_args, **_options)
        (positions || []).each_with_object({}) do |position, wire|
          entry = {}
          entry['position_on'] = position.position_on unless position.position_on.nil?
          entry['datasets'] = position.datasets unless position.datasets.nil?
          wire[position.publication_id] = entry.empty? ? nil : entry
        end
      end

      def to_yaml(*_args, **_options)
        to_hash.to_yaml
      end

      def publication_ids
        (positions || []).map(&:publication_id)
      end

      def position_for(publication_id)
        (positions || []).find { |position| position.publication_id == publication_id }
      end
    end
  end
end
