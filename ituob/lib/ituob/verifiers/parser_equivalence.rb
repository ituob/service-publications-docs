# frozen_string_literal: true

module Ituob
  module Verifiers
    # Pure functions behind scripts/verify_parser_equivalence.rb.
    #
    # The script owns I/O (globbing source amendments, reading/writing
    # baseline JSON); this module owns the semantics:
    #
    #   serialize(parsed)  → deterministic serialization of one parsed
    #                        amendment (actions to_hash + notes)
    #   diffs(b, c)        → sorted issue keys whose serializations
    #                        differ between baseline +b+ and current +c+
    module ParserEquivalence
      module_function

      def serialize(parsed)
        {
          'actions' => parsed.actions.map(&:to_hash),
          'notes' => parsed.notes,
        }
      end

      # +baseline+ and +current+ map issue id → serialized amendment.
      # Returns issue ids that are missing on either side or differ.
      def diffs(baseline, current)
        (baseline.keys + current.keys).uniq.sort.select do |issue|
          JSON.generate(baseline[issue]) != JSON.generate(current[issue])
        end
      end
    end
  end
end
