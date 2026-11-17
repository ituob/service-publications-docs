# frozen_string_literal: true

module Ituob
  module Models
    # Compares captured/recovered rows with independently parsed printed rows.
    # Office aliases and unresolved network-relative families are compared as
    # printed assignments, not invented full destination indicators.
    class F32CompletenessChecker
      def initialize(reference:, candidates:, candidate_source:)
        @reference = reference
        @candidates = candidates
        @candidate_source = candidate_source
      end

      def compare
        expected = reference_rows.group_by { |entry| identity(entry) }
        actual = @candidates.select { |entry| present?(entry.office_code) }.group_by { |entry| identity(entry) }
        report = F32CompletenessReport.new(
          source_uri: @reference.source_uri, source_sha256: @reference.source_sha256,
          candidate_source: @candidate_source, candidate_rows: @candidates.length,
          candidate_context_rows: @candidates.count { |entry| !present?(entry.office_code) }
        )
        totals = Hash.new { |hash, key| hash[key] = [0, 0, 0, 0] }
        (expected.keys | actual.keys).sort.each do |key|
          printed = expected.fetch(key, [])
          captured = actual.fetch(key, [])
          country = (printed.first || captured.first).country_or_area&.fr.to_s
          unmatched = captured.dup
          absent = []
          printed.each do |source|
            index = unmatched.index { |entry| same_name?(entry, source) }
            if index
              unmatched.delete_at(index)
              report.matching_keys << "#{key}: #{source.telegraph_office_name&.en}"
              totals[country][0] += 1
            else
              absent << source
            end
          end
          if absent.length == 1 && unmatched.length == 1
            report.different << difference(unmatched.first, absent.first, "Printed office name differs")
            totals[country][3] += 1
          else
            absent.each { |source| report.missing << difference(nil, source, "Printed assignment absent from recovered rows") }
            unmatched.each { |entry| report.extra << difference(entry, nil, "Recovered assignment absent from print") }
            totals[country][1] += absent.length
            totals[country][2] += unmatched.length
          end
        end
        totals.sort.each do |country, values|
          report.countries << F32CountryCompleteness.new(
            country: country, matching: values[0], missing: values[1], extra: values[2], different: values[3]
          )
        end
        report
      end

      private

      def reference_rows
        @reference.allocations + @reference.contexts.filter_map do |context|
          context.entry if %w[shared-indicator network-relative-office].include?(context.kind)
        end
      end

      def identity(entry)
        code = entry.office_code.to_s
        return code if code.match?(/\A[A-Z]{4}\z/)

        "#{normalize(entry.country_or_area&.fr)} / #{code}"
      end

      def same_name?(actual, expected)
        normalize(actual.telegraph_office_name&.en) == normalize(expected.telegraph_office_name&.en)
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfc).gsub(/\s*\(?\d+\)\s*\z/, "").gsub(/[[:space:]\u00a0]+/, " ").strip.upcase
      end

      def difference(actual, expected, reason)
        entry = expected || actual
        F32OfficeDifference.new(country: entry.country_or_area&.fr, office_code: entry.office_code,
                               expected: expected, actual: actual, reason: reason)
      end

      def present?(value)
        value && !value.gsub(/[[:space:]\u00a0]/, "").empty?
      end
    end
  end
end
