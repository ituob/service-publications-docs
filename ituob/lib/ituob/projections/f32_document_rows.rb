# frozen_string_literal: true

module Ituob
  module Projections
    # The printed list includes ambiguous suffixes, shared offices and cross
    # references that must not become canonical allocations in register replay.
    class F32DocumentRows
      OFFICE_CONTEXTS = %w[network-relative-office shared-indicator alias printed-unassigned].freeze
      NETWORK_CONTEXTS = %w[network reservation telex].freeze

      def initialize(items:, contexts:)
        @items = items
        @contexts = contexts
      end

      def rows
        printed = @contexts.select do |context|
          OFFICE_CONTEXTS.include?(context.kind) && context.source_path.to_s.end_with?(".pdf")
        end.map(&:entry)
        offices = @items + printed
        networks = @contexts.select do |context|
          NETWORK_CONTEXTS.include?(context.kind) && network_needed?(context.entry, offices)
        end.map(&:entry)
        result = offices + networks
        # A country can have a heading without any currently allocated office.
        @contexts.select { |context| context.kind == "heading" }.each do |context|
          result << context.entry unless result.any? { |entry| country(entry) == country(context.entry) }
        end
        anchors = result.each_with_object({}) do |entry, positions|
          next unless entry.source_row

          key = country(entry)
          positions[key] = [positions[key] || entry.source_row, entry.source_row].min
        end
        # Legacy annotations without print coordinates belong with their country.
        ordered = result.sort_by do |entry|
          [entry.source_row || anchors[country(entry)] || Float::INFINITY, entry.source_page || 0]
        end
        normalize_saudi_legends(ordered)
      end

      private

      # The source prints one shared legend after the five routing notes. The
      # legacy capture appended it to every note (twice in the Makkah note).
      def normalize_saudi_legends(rows)
        rows = rows.map do |entry|
          country(entry) == "SAUDI ARABIA" && entry.notes ? Models::F32TDIEntry.from_yaml(entry.to_yaml) : entry
        end
        notes = rows.select { |entry| country(entry) == "SAUDI ARABIA" && entry.notes }.map(&:notes)
        {
          en: /\s*\(i\)\s+Seasonal Opening\.\s+\(ii\)\s+Main Telegraph Office\./,
          fr: /\s*\(i\)\s+Ouverture saisonnière\.\s+\(ii\)\s+Bureau télégraphique principal\./,
          es: /\s*\(i\)\s+Apertura estacional\.\s+\(ii\)\s+Oficina telegráfica principal\./
        }.each do |language, pattern|
          legend = nil
          notes.each do |note|
            value = note.public_send(language)
            next unless value

            legend ||= value[pattern]&.strip&.gsub(/\s+/, " ")
            note.public_send("#{language}=", value.gsub(pattern, "").strip)
          end
          next unless legend

          last = notes.reverse.find { |note| !note.public_send(language).to_s.empty? }
          last.public_send("#{language}=", "#{last.public_send(language)} #{legend}")
        end
        rows
      end

      def country(entry)
        entry.country_or_area&.en.to_s.upcase.gsub(/[[:space:]]+/, " ").strip.delete_suffix("1)").strip
      end

      def network_needed?(entry, offices)
        return true if entry.network_code_note || entry.network_roa_note || entry.country_or_area_note

        prefix = entry.network_code.to_s[/[A-Z]{2}/]
        !offices.any? do |office|
          country(office) == country(entry) && office.office_code.to_s.start_with?(prefix.to_s)
        end
      end
    end
  end
end
