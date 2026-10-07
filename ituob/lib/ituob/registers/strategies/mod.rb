# frozen_string_literal: true

module Ituob
  module Registers
    module Strategies
      # MOD — partial update. Merges +change.data+ into the existing
      # entry. +merge_strategy+ controls depth:
      #   * replace_fields (default) — top-level field merge.
      #   * replace_full — wholesale replacement (same as REP).
      class Mod < Base
        extend Ituob::Support::HashField

        def self.validate!(builder, change, key)
          return if builder.entries.key?(key)

          raise StrategyError,
                "MOD conflict: key #{key.inspect} not present in register #{change.register_id}"
        end

        def self.apply(builder, change, key_field, key)
          existing = builder.entries[key] || {}
          merged =
            if change.merge_strategy == 'replace_full'
              (change.data&.dup) || {}
            else
              merge_fields(existing, change.data)
            end
          set(merged, key_field, key)
          builder.set_entry(key, merged)
          builder.clear_lapsed(key)
        end

        # Deep-merge the patch into the existing entry. When both the
        # existing and patch values for a key are Hashes, recurse
        # instead of replacing wholesale. This preserves multilingual
        # fields like `{message: {en: "x"}}` when only one language
        # is updated.
        def self.merge_fields(existing, patch)
          return existing.dup if patch.nil?

          result = existing.dup
          patch.each do |k, v|
            if v.is_a?(Hash) && result[k].is_a?(Hash)
              result[k] = deep_merge_hashes(result[k], v)
            elsif !v.nil?
              result[k] = v
            end
          end
          result
        end

        def self.deep_merge_hashes(base, overlay)
          merged = base.dup
          overlay.each do |k, v|
            if v.is_a?(Hash) && merged[k].is_a?(Hash)
              merged[k] = deep_merge_hashes(merged[k], v)
            elsif !v.nil?
              merged[k] = v
            end
          end
          merged
        end
        private_class_method :merge_fields, :deep_merge_hashes
      end
    end
  end
end
