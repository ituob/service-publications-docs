# frozen_string_literal: true

require 'yaml'
require 'time'
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
    # are all kept as stored, including null versus empty mappings. Unedited
    # YAML retains its original bytes; edits serialize the current model.
    # Unknown entry keys and invalid positions raise at the load boundary.
    class IssueAnnexes < Lutaml::Model::Serializable
      ENTRY_KEYS = %w[position_on datasets].freeze
      TYPE_TAG = '__type__'

      attribute :positions, AnnexedPosition, collection: true

      def self.from_hash(hash, *_args, **_options)
        raise ArgumentError, 'annexes must be a mapping of publication id to position' unless hash.is_a?(Hash)

        # Only the adapter's scalar type-name tag is metadata. A mapping
        # or null under __type__ is an ordinary publication.
        adapter = hash[TYPE_TAG] == 'IssueAnnexes'
        entries = adapter ? hash.reject { |id, _| id == TYPE_TAG } : hash
        new(positions: entries.map { |id, entry| position_from(id, entry, adapter: adapter) })
      end

      def self.from_yaml(yaml, *_args, **options)
        yaml = yaml.read if yaml.respond_to?(:read)
        # Psych uses YAML 1.1 booleans, while the site's YAML 1.2 reader
        # treats yes/no/on/off as strings. Retag only publication keys,
        # before the Hash constructor can collapse their identities.
        tree = Psych.parse_stream(yaml)
        root = tree.children.first&.root
        if root.is_a?(Psych::Nodes::Mapping)
          root.children.each_slice(2) do |key, _|
            next unless key.is_a?(Psych::Nodes::Scalar) && key.plain && key.tag.nil?
            next unless key.value.match?(/\A(?:yes|no|on|off)\z/i)

            key.tag = 'tag:yaml.org,2002:str'
            key.plain = false
            key.quoted = true
            key.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
          end
        end
        data = YAML.safe_load(tree.to_yaml, permitted_classes: options.fetch(:permitted_classes, [Date, Time]), aliases: true)
        model = from_hash(data.nil? ? {} : data)
        model.remember_source(yaml)
        model
      end

      def self.position_from(id, entry, adapter: false)
        return AnnexedPosition.new(publication_id: id) if entry.nil?
        raise ArgumentError, "#{id}: position must be a mapping or null" unless entry.is_a?(Hash)

        unknown = entry.keys.map(&:to_s) - ENTRY_KEYS
        raise ArgumentError, "#{id}: unknown annex keys #{unknown.sort.inspect}" unless unknown.empty?

        entry = entry.transform_keys(&:to_s)
        value = entry['position_on']
        # LML instances have date strings rather than YAML date scalars.
        if adapter && value.is_a?(String)
          value = case value
                  when /\A\d{4}-\d{2}-\d{2}\z/ then Date.iso8601(value)
                  when /\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (?:UTC|[+-]\d{4})\z/
                    Time.strptime(value, '%Y-%m-%d %H:%M:%S %Z')
                  else Time.iso8601(value)
                  end
        end
        unless value.nil? || value.is_a?(Date) || value.is_a?(Time)
          raise ArgumentError, "#{id}: position_on must be a date, timestamp or null"
        end

        position = AnnexedPosition.new(publication_id: id, position_on: value, datasets: entry['datasets'])
        position.entry_keys = entry.keys
        position
      end
      private_class_method :position_from

      def to_hash(*_args, **_options)
        (positions || []).each_with_object({}) do |position, wire|
          values = { 'position_on' => position.position_on, 'datasets' => position.datasets }
          keys = ((position.entry_keys || []) + values.keys.reject { |key| values[key].nil? }).uniq
          entry = keys.to_h { |key| [key, values[key]] }
          wire[position.publication_id] = entry.empty? && position.entry_keys.nil? ? nil : entry
        end
      end

      def to_yaml(*_args, **_options)
        return @source_yaml.dup if @source_yaml && @source_state == Marshal.dump(to_hash)

        to_hash.to_yaml
      end

      def remember_source(yaml)
        @source_yaml = yaml.dup
        @source_state = Marshal.dump(to_hash)
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
