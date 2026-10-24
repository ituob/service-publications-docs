# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # Protocol all strategies implement.
      #
      # +call(builder, change, key_field)+ applies one change. The
      # affected keys come from the change DATA when it carries
      # keyable rows — +data['entries'][]+ for multi-row amendments,
      # or +data+ itself when it is a single row with the register's
      # +key_field+ (e.g. E164_CC patches keyed by +cc_ic+). The
      # declared identifier code is only the fallback; for many
      # printed amendments it records the table position ("P 19"),
      # which is not a key.
      #
      # When rows are data-derived, validation runs for every key
      # BEFORE any mutation (a change applies atomically or not at
      # all).
      class Base
        # Does this strategy destroy or remove data? Default false.
        # Destructive strategies (SUP, DEL) override to return true.
        # Used by +ActionType#destructive?+ so the classification
        # lives with the strategy, not in ActionType.
        def self.destructive?
          false
        end

        # Row hashes this change operates on. Empty when the data
        # shape carries no rows keyed by +key_field+ (or a declared
        # fallback field).
        def self.rows_for(change, key_field, fallbacks = [])
          data = change.data
          return [] unless data.is_a?(Hash)

          entries = data['entries']
          if entries.is_a?(Array)
            return entries.select { |e| e.is_a?(Hash) && entry_key(e, key_field, fallbacks) }
          end

          entry_key(data, key_field, fallbacks) ? [data] : []
        end

        # Key of one row: the primary key field, then any declared
        # fallback fields. Hash values (multilingual strings) resolve
        # to their first non-empty entry in the OB canonical language
        # order, matching how the printed list reads.
        # +key_field+ may be a single field name or an array naming a
        # composite key (registers whose rows have no unique single
        # field, e.g. F32_TDI). Hash values (multilingual strings)
        # resolve to their first non-empty entry in the OB canonical
        # language order, matching how the printed list reads.
        def self.entry_key(row, key_field, fallbacks = [])
          parts = Array(key_field).map do |field|
            value = row[field] || row[field.to_sym]
            case value
            when Hash then canonical_language(value)
            when nil then nil
            else value.to_s
            end
          end
          return nil if parts.all? { |p| p.nil? || p.empty? }

          parts.map { |p| p.nil? || p.empty? ? '' : p }.join(' | ')
        end

        # Canonical OB language order (matches the site renderer).
        LANGUAGE_KEYS = %w[fr en es zh ru ar].freeze

        def self.canonical_language(hash)
          key = LANGUAGE_KEYS.find { |l| v = hash[l] || hash[l.to_sym]; v.is_a?(String) && !v.empty? }
          key && (hash[key] || hash[key.to_sym])
        end

        # Resolve the key (string) that a change targets, given the
        # current builder state — the legacy single-key path used when
        # the data shape carries no keyable rows. For direct
        # identifiers this is the declared code; for query identifiers
        # the builder performs the lookup.
        def self.resolve_key(builder, change, key_field, fallbacks = [])
          if change.identifier.direct?
            change.identifier.code
          else
            builder.find_key_by_query(change.identifier, key_field)
          end
        end

        # Hook: raise when preconditions are not met.
        # Subclasses override to enforce "must exist" / "must not
        # exist" invariants.
        def self.validate!(builder, change, key, _row = nil); end

        # Hook: perform the mutation. Subclasses override.
        def self.apply(builder, change, key_field, key, fallbacks = [])
          raise NotImplementedError, "#{name}.apply not implemented"
        end

        # Hook: mutate one data-derived row. Default: ignore the row
        # payload and apply by key alone.
        def self.apply_row(builder, change, key_field, key, row, fallbacks = [])
          apply(builder, change, key_field, key, fallbacks)
        end

        # Common entry: validate then apply. Data-derived keys are
        # validated as a set first so a partial change never half-
        # applies.
        def self.call(builder, change, key_field, fallbacks = [])
          rows = rows_for(change, key_field, fallbacks)
          if rows.empty?
            key = resolve_key(builder, change, key_field, fallbacks)
            validate!(builder, change, key)
            apply(builder, change, key_field, key, fallbacks)
            return
          end

          keys = rows.map { |r| entry_key(r, key_field, fallbacks) }
          keys.each_with_index { |k, i| validate!(builder, change, k, rows[i]) }
          keys.each_with_index { |k, i| apply_row(builder, change, key_field, k, rows[i], fallbacks) }
        end
      end
    end
  end
end
