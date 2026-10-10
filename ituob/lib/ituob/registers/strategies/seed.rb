# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # SEED — the initial publication batch. +data+ is an array of
      # rows. The strategy expands the batch into N implicit ADD
      # operations at the seed-issue ob_issue_no.
      #
      # If a row already exists (e.g., on a re-run), it is treated as
      # REP (idempotent). The key is derived from +key_field+.
      class Seed < Base
        extend Ituob::Support::HashField

        def self.apply(builder, change, key_field, _key)
          rows = Array(change.data)
          rows.each do |row|
            row_key = lookup(row, key_field)
            next if row_key.nil? || row_key.to_s.empty?

            builder.set_entry(row_key.to_s, row.dup)
            builder.clear_lapsed(row_key.to_s)
            builder.clear_deleted(row_key.to_s)
          end
        end

        # SEED doesn't use identifier resolution — its target is the
        # entire batch, not a single key.
        def self.resolve_key(_builder, _change, _key_field)
          nil
        end
      end
    end
  end
end
