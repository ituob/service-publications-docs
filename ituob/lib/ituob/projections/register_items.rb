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

      def initialize(register:)
        @register = register
      end

      def at_issue(issue)
        hydrate(state_at(issue))
      end

      # Replayed register state at the end of OB issue +issue+.
      def state_at(issue)
        entry_class
        replay.at_issue(issue)
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
        Registers::DirectoryChangeSource.new(
          register_id: @register.register_id,
          seed_path: File.expand_path(@register.seed_path, DataRoot.path),
          seed_issue: @register.seed_issue,
          key_field: @register.key_field
        )
      end
    end
  end
end
