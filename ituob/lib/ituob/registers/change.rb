# frozen_string_literal: true

require 'lutaml/model'

module Ituob
  module Registers
    class Change < Lutaml::Model::Serializable
      include Comparable
      include Ituob::Support::DeepFreeze

      attribute :type, :string
      attribute :register_id, :string
      attribute :identifier, Identifier
      attribute :recommendation, :string
      attribute :data, :hash
      attribute :ob_issue_no, :integer
      attribute :date_active, :string
      attribute :date_requested, :string
      attribute :reference, :string
      attribute :description, :hash
      attribute :superseded_by, :hash
      attribute :reason, :hash
      attribute :merge_strategy, :string

      key_value do
        map :type, to: :type
        map :register, to: :register_id
        map :identifier, to: :identifier
        map :recommendation, to: :recommendation
        map :data, to: :data
        map :ob_issue_no, to: :ob_issue_no
        map :date_active, to: :date_active
        map :date_requested, to: :date_requested
        map :reference, to: :reference
        map :description, to: :description
        map :superseded_by, to: :superseded_by
        map :reason, to: :reason
        map :merge_strategy, to: :merge_strategy
      end

      def initialize(type: nil, register_id: nil, identifier: nil, recommendation: nil,
                     data: nil, ob_issue_no: nil, date_active: nil,
                     date_requested: nil, reference: nil,
                     description: nil, superseded_by: nil, reason: nil,
                     merge_strategy: nil)
        super()
        return unless type || register_id

        self.type = ActionType.coerce(type).value
        self.register_id = register_id.to_s
        self.identifier = identifier.is_a?(Identifier) ? identifier : Identifier.from_hash(identifier || {})
        self.recommendation = recommendation
        self.data = data
        Ituob::Support::DeepFreeze.deep_freeze(self.data) if self.data
        self.ob_issue_no = ob_issue_no&.to_i
        self.date_active = date_active
        self.date_requested = date_requested
        self.reference = reference
        self.description = description && description.transform_keys(&:to_s)
        self.superseded_by = superseded_by && superseded_by.transform_keys(&:to_s)
        self.reason = reason && reason.transform_keys(&:to_s)
        self.merge_strategy = merge_strategy || 'replace_fields'
        freeze
      end

      def self.from_hash(hash)
        hash = hash.to_h if hash.is_a?(Hash)
        instance = super
        instance.type = ActionType.coerce(instance.type).value
        instance.merge_strategy = 'replace_fields' if instance.merge_strategy.nil? || instance.merge_strategy == ''
        Ituob::Support::DeepFreeze.deep_freeze(instance.data) if instance.data
        instance.freeze
      end

      def action_type
        ActionType.coerce(type)
      end

      def seed? = action_type.seed?
      def add? = action_type.add?
      def sup? = action_type.sup?
      def rep? = action_type.rep?
      def lir? = action_type.lir?
      def mod? = action_type.mod?
      def del? = action_type.del?

      def <=>(other)
        return nil unless other.is_a?(Change)

        cmp = (ob_issue_no || Float::INFINITY) <=> (other.ob_issue_no || Float::INFINITY)
        return cmp if cmp != 0

        (identifier.code || '') <=> (other.identifier.code || '')
      end
    end
  end
end
