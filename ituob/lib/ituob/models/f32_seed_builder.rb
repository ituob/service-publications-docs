# frozen_string_literal: true

require "digest"
require "ituob/support"

module Ituob
  module Models
    # Separates printed network/context records from actual office allocations.
    # Original entries remain typed and are serialized by the LML models.
    class F32SeedBuilder
      RULES_PATH = File.expand_path("../../../../catalogs/f32_seed_contexts.yaml", __dir__)

      def initialize(seed_path:, source_sha256: nil, source_path: "datasets/980-F.32/data.yaml")
        @seed_path = seed_path
        @rules = Ituob::Support::Yaml.safe_load_file(RULES_PATH)
        @source_sha256 = source_sha256
        @source_path = source_path
      end

      def build
        publication = F32SeedPublication.new(
          source_uri: @rules.fetch("source_uri"), source_sha256: @source_sha256,
          source_position_on: @rules.fetch("position_on"), source_path: @source_path,
          seed_sha256: Digest::SHA256.file(@seed_path).hexdigest,
          source_complete: false
        )
        rows = Ituob::Support::Yaml.safe_load_file(@seed_path).map { |row| F32TDIEntry.from_hash(row) }
        publication.legacy_rows.concat(rows.map { |entry| clone_entry(entry) })
        publication.source_row_count = rows.length
        allocated = {}
        networks = Hash.new { |hash, key| hash[key] = [] }
        rows.each_with_index do |entry, index|
          country = entry.country_or_area&.fr
          prefix = entry.network_code.to_s[/\A[A-Z]{2}/]
          networks[country] << prefix if prefix && !networks[country].include?(prefix)
          if present?(entry.office_code)
            if entry.office_code.start_with?("--")
              choices = prefix ? [prefix] : networks[country]
              if choices.length == 1
                entry = clone_entry(entry)
                entry.office_code = choices.first + entry.office_code.delete_prefix("--")
              else
                publication.contexts << F32SeedContext.new(ob_issue_no: 980,
                  kind: "network-relative-office", entry: clone_entry(entry), network_codes: choices.dup,
                  source_uri: @rules.fetch("source_uri"), source_path: @source_path, source_row: index + 1,
                  related_office_code: entry.office_code,
                  explanation: "Printed office suffix has multiple network codes; no single full indicator is asserted."
                )
                next
              end
            end
            key = entry.office_code
            if allocated.key?(key)
              publication.contexts << F32SeedContext.new(ob_issue_no: 980,
                kind: "shared-indicator", entry: clone_entry(entry),
                related_office_code: entry.office_code, source_uri: @rules.fetch("source_uri"),
                source_path: @source_path, source_row: index + 1,
                explanation: "Another printed office name served by the same destination indicator; see source page 2."
              )
            else
              publication.allocations << clone_entry(entry)
              allocated[key] = true
            end
            next
          end

          context = context_for(entry, index, rows)
          publication.contexts << context
          next unless context.kind == "continuation"

          # A continuation only applies to its catalog-proved immediately following row.
          target = rows.fetch(index + 1)
          normalized = clone_entry(target)
          normalized.telegraph_office_name = joined_name(entry.telegraph_office_name, target.telegraph_office_name)
          rows[index + 1] = normalized
        end
        publication
      end

      # The complete publication is independently parsed from print. The old
      # capture is retained verbatim as typed rows, never treated as its oracle.
      def build_complete(xml_path:, pdf_path:)
        legacy = build
        printed = F32PrintedList.new(xml_path: xml_path, pdf_path: pdf_path).parse
        printed.seed_sha256 = legacy.seed_sha256
        printed.legacy_rows = legacy.legacy_rows
        preserve_legacy_annotations(printed, legacy)
        legacy.contexts.each do |record|
          if %w[network reservation telex].include?(record.kind) && record.entry.network_code
            prefix = record.entry.network_code[/\A[A-Z]{2}/]
            counterpart = printed.contexts.find do |candidate|
              candidate.kind == "network" && candidate.entry.network_code.to_s.start_with?(prefix.to_s)
            end
            if counterpart
              record.source_page ||= counterpart.source_page
              printed.contexts.delete(counterpart)
            end
          end
          printed.contexts << record
        end
        printed
      end

      private

      def context_for(entry, index, rows)
        country = entry.country_or_area&.en
        text = entry.telegraph_office_name&.en
        continuation = rule_for("continuations", country, text)
        unassigned = rule_for("unassigned", country, text)
        context = F32SeedContext.new(ob_issue_no: 980,
          entry: clone_entry(entry), source_uri: @rules.fetch("source_uri"),
          source_path: @source_path, source_row: index + 1
        )
        notes = [entry.network_code_note, entry.country_or_area_note].compact.flat_map do |value|
          value.class.attributes.keys.map { |language| value.public_send(language).to_s }
        end.join(" ")
        if continuation
          target = rows[index + 1]
          unless target && target.office_code == continuation.fetch("following_code") &&
              target.country_or_area&.en == country
            raise "F32 continuation at source row #{index + 1} does not precede its printed office"
          end
          context.kind = "continuation"
          context.source_page = continuation.fetch("page")
          context.related_office_code = target.office_code
          context.continuation_target = clone_entry(target)
        elsif unassigned
          context.kind = "printed-unassigned"
          context.source_page = unassigned.fetch("page")
          context.explanation = unassigned.fetch("explanation")
        elsif text&.include?("-->")
          context.kind = "alias"
          context.explanation = "Printed name cross-reference; no office code is assigned in this row."
        elsif notes.match?(/telex|télex/i)
          context.kind = "telex"
        elsif notes.match?(/remain\w* reserved|reste\w* réservé|permanece\w* reservado/i)
          context.kind = "reservation"
        elsif !present?(text) && present?(entry.network_code)
          context.kind = "network"
          context.explanation = "Network indicator (first two letters), distinct from an office allocation; see source page 2."
          context.source_page = 2
        else
          raise "Unclassified F32 source row #{index + 1}: #{country.inspect} #{text.inspect}"
        end
        context
      end

      def rule_for(name, country, text)
        @rules.fetch(name).find { |rule| rule.fetch("country") == country && rule.fetch("text") == text }
      end

      def clone_entry(entry)
        F32TDIEntry.from_yaml(entry.to_yaml)
      end

      def preserve_legacy_annotations(printed, legacy)
        legacy_by_code = legacy.legacy_rows.select do |entry|
          entry.office_code.to_s.match?(/\A[A-Z]{4}\z/)
        end.group_by(&:office_code)
        annotation_fields = %i[
          country_or_area_note notes network_roa_note network_code_note office_code_note subarea
        ]
        printed.allocations.each do |entry|
          candidates = legacy_by_code.fetch(entry.office_code, [])
          old = candidates.find do |candidate|
            normalized_name(candidate.telegraph_office_name&.en) ==
              normalized_name(entry.telegraph_office_name&.en)
          end || candidates.first
          next unless old

          annotation_fields.each do |field|
            value = old.public_send(field)
            entry.public_send("#{field}=", clone_value(value)) unless value.nil?
          end
        end
      end

      def clone_value(value)
        value.class.from_yaml(value.to_yaml)
      end

      def normalized_name(value)
        value.to_s.unicode_normalize(:nfc).gsub(/[[:space:]\u00a0]+/, " ").strip.upcase
      end

      def joined_name(prefix, suffix)
        result = MultilingualString.from_yaml(suffix.to_yaml)
        prefix.class.attributes.each_key do |language|
          first = prefix.public_send(language)
          next unless present?(first)

          result.public_send("#{language}=", [first, suffix.public_send(language)].compact.join(" "))
        end
        result
      end

      def present?(value)
        value && !value.gsub(/[[:space:]\u00a0]/, "").empty?
      end
    end
  end
end
