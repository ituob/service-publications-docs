# frozen_string_literal: true

module Ituob
  module Projections
    # Hydrates replayed rows using the register's compiled LML Entry model.
    #
    #   register = Ituob::Catalogs::Registers.find('E212_MNC')
    #   RegisterItems.new(register: register).at_issue(1170)
    #
    # Returns an array of Entry objects in State#active_entries key order.
    # Raises UnsupportedRegisterError for registers without a compiled Entry
    # class, including textual/external registers.
    class RegisterItems
      class UnsupportedRegisterError < ArgumentError; end
      class MissingSeedError < ArgumentError; end
      class InvalidSeedError < ArgumentError; end

      def initialize(register:)
        @register = register
      end

      def at_issue(issue)
        hydrate(state_at(issue))
      end

      # The published seed is an ordered list: shared identifiers are distinct
      # printed rows, even though replay groups active membership by key.
      def seed_items
        model = entry_class
        seed = change_source.each_sorted.find(&:seed?)
        raise MissingSeedError, "Register #{@register.register_id} has no publication seed" unless seed

        unless seed.data.is_a?(Array) && !seed.data.empty?
          raise InvalidSeedError, "Register #{@register.register_id} publication seed must contain rows"
        end

        seed.data.each_with_index.map do |row, index|
          unless row.is_a?(Hash) && !row.empty?
            raise InvalidSeedError, "Register #{@register.register_id} publication seed row #{index + 1} must be a nonempty mapping"
          end

          item = model.from_hash(row.merge('_class' => model.name.split('::').last))
          validate_publication_fields!(row, item.to_hash, "row #{index + 1}")
          item
        end
      end

      # Replayed register state at the end of OB issue +issue+.
      def state_at(issue)
        entry_class
        replay.at_issue(issue)
      end

      def source_contexts_at(issue)
        source = change_source
        return [] unless source.respond_to?(:contexts_at_issue)

        source.contexts_at_issue(issue)
      end

      # Entry instances for the active rows of +state+, in replay key
      # order. Each carries its concrete class name as the `_class`
      # discriminator so a RegisterEdition restores the same classes.
      def hydrate(state)
        model = entry_class
        state.active_entries.values.map do |row|
          model.from_hash(row.merge('_class' => model.name.split('::').last))
        end
      end

      private

      # Typed hydration must not silently discard a new publication column or
      # nested language. Nulls and empty collections may be omitted by LML.
      def validate_publication_fields!(source, result, path)
        case source
        when Hash
          source.each do |key, value|
            next if value.nil? || value == [] || value == {}

            field = "#{path}.#{key}"
            unless result.is_a?(Hash) && result.key?(key)
              raise InvalidSeedError, "Register #{@register.register_id} publication seed loses #{field}"
            end
            validate_publication_fields!(value, result[key], field)
          end
        when Array
          unless result.is_a?(Array) && source.size == result.size
            raise InvalidSeedError, "Register #{@register.register_id} publication seed loses #{path}"
          end
          source.zip(result).each_with_index do |(value, projected), index|
            validate_publication_fields!(value, projected, "#{path}[#{index}]")
          end
        end
      end

      def entry_class
        parser = Catalogs::Registers.parser_class_for(@register.register_id)
        model = parser&.attributes&.dig(:entries)&.type
        return model if model

        raise UnsupportedRegisterError,
              "Register #{@register.register_id} has no compiled Entry class"
      end

      def replay
        Registers::Replay.new(
          register_id: @register.register_id,
          key_field: @register.key_field,
          fallback_key_fields: @register.fallback_key_fields,
          source: change_source
        )
      end

      def change_source
        @change_source ||= Registers::DirectoryChangeSource.for_register(
          register_id: @register.register_id,
          seed_path: File.expand_path(@register.seed_path, DataRoot.path),
          seed_issue: @register.seed_issue,
          seed_includes_seed_issue: @register.seed_includes_seed_issue,
          key_field: @register.key_field
        )
      end
    end
  end
end
