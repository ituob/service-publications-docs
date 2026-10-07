# frozen_string_literal: true

require 'lutaml/model'
require 'set'

module Ituob
  module Registers
    # Immutable value object: the structured diff between two +State+s
    # of the same register at different OB issues.
    #
    # Returned by +Replay#diff(from_issue, to_issue)+. All key arrays
    # are sorted for deterministic comparison.
    #
    # Serialized via +lutaml-model+ (no hand-rolled +to_h+). Use
    # +to_hash+ / +from_hash+ for the canonical wire shape.
    class StateDiff < Lutaml::Model::Serializable
      attribute :from_issue, :integer
      attribute :to_issue, :integer
      attribute :added_keys, :string, collection: true
      attribute :removed_keys, :string, collection: true
      attribute :modified_keys, :string, collection: true
      attribute :lapsed_keys, :string, collection: true
      attribute :unlapsed_keys, :string, collection: true

      key_value do
        map :from_issue, to: :from_issue
        map :to_issue, to: :to_issue
        map :added_keys, to: :added_keys
        map :removed_keys, to: :removed_keys
        map :modified_keys, to: :modified_keys
        map :lapsed_keys, to: :lapsed_keys
        map :unlapsed_keys, to: :unlapsed_keys
      end

      # Hook: sort all key arrays + freeze after construction so the
      # value object is immutable and deterministic.
      def self.from_hash(hash)
        instance = super
        normalize_instance(instance)
      end

      def self.normalize_instance(instance)
        instance.added_keys.sort!.freeze
        instance.removed_keys.sort!.freeze
        instance.modified_keys.sort!.freeze
        instance.lapsed_keys.sort!.freeze
        instance.unlapsed_keys.sort!.freeze
        instance.freeze
      end
      private_class_method :normalize_instance

      # True when no field changed between the two states.
      def empty?
        added_keys.empty? && removed_keys.empty? &&
          modified_keys.empty? && lapsed_keys.empty? &&
          unlapsed_keys.empty?
      end

      def total_change_count
        added_keys.length + removed_keys.length +
          modified_keys.length + lapsed_keys.length +
          unlapsed_keys.length
      end

      # Compute a StateDiff between two States of the same register.
      # Both inputs must be frozen State instances (asserted at
      # construction time by Replay). Returns a frozen StateDiff.
      def self.between(from_state, to_state)
        from_entries = from_state.entries
        to_entries = to_state.entries

        from_keys = Set.new(from_entries.keys)
        to_keys = Set.new(to_entries.keys)

        added = to_keys - from_keys
        removed = from_keys - to_keys
        common = from_keys & to_keys

        modified = common.select do |k|
          from_entries[k] != to_entries[k]
        end

        from_lapsed = Set.new(from_state.lapsed_keys)
        to_lapsed = Set.new(to_state.lapsed_keys)

        newly_lapsed = to_lapsed - from_lapsed
        # unlapsed: was lapsed, now active (entry still exists).
        unlapsed = (from_lapsed - to_lapsed).select { |k| to_entries.key?(k) }

        from_hash(
          'from_issue' => from_state.at_ob_issue,
          'to_issue' => to_state.at_ob_issue,
          'added_keys' => added.to_a,
          'removed_keys' => removed.to_a,
          'modified_keys' => modified.to_a,
          'lapsed_keys' => newly_lapsed.to_a,
          'unlapsed_keys' => unlapsed.to_a,
        )
      end
    end
  end
end
