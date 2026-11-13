# frozen_string_literal: true

require "digest"
require "ituob/models"

module Ituob
  module Registers
    # Reads the explicitly verified F.32 publication while retaining its context.
    # An absent artifact keeps the old source visible as an unverified fallback.
    class F32DirectoryChangeSource < DirectoryChangeSource
      PUBLICATION_FILENAME = "publication.yaml"
      CONTEXT_KINDS = %w[heading network reservation telex alias continuation printed-unassigned shared-indicator network-relative-office aggregated-office-action].freeze

      attr_reader :publication, :context_only_changes, :context_only_sources

      def initialize(**options)
        super
        @amendment_contexts = []
        @context_only_changes = []
        @context_only_sources = []
        return unless @register_id == "F32_TDI"

        path = File.join(seed_path, PUBLICATION_FILENAME)
        if File.file?(path)
          @publication = Models::F32SeedPublication.from_yaml(File.read(path))
          validate_publication!
        else
          warn "F32 seed uses legacy data.yaml: independent allocation completeness has not been verified"
        end
      end

      def legacy_seed?
        publication.nil?
      end

      # Context is a first-class edition input, including context-only actions.
      # Canonical event files remain the durable source for these later records.
      def contexts_at_issue(issue = nil)
        each_sorted { |_change| nil }
        seed_contexts = publication ? publication.contexts : []
        (seed_contexts + @amendment_contexts).select do |context|
          issue.nil? || context.ob_issue_no.to_i <= issue.to_i
        end
      end

      private

      def load_yaml(path)
        @loaded_path = path
        super
      end

      def each_amendment
        return enum_for(:each_amendment) unless block_given?
        return super unless publication

        @amendment_contexts = []
        @context_only_changes = []
        @context_only_sources = []
        super do |change|
          if change.ob_issue_no && change.ob_issue_no < seed_issue
            yield change
            next
          end
          data = change.data
          rows = if data.is_a?(Hash) && data['entries'].is_a?(Array)
                   data['entries']
                 elsif data.is_a?(Hash) && data.key?('office_code')
                   [data]
                 else
                   []
                 end
          if rows.empty?
            yield change
            next
          end
          offices = rows.each_with_index.flat_map do |row, index|
            entry = Models::F32TDIEntry.from_hash(row)
            code = entry.office_code.to_s.strip
            if code.empty?
              @amendment_contexts << amendment_context(change, entry, index, [], kind: 'heading')
              next []
            end

            codes = code.split(/[[:space:]\u00a0]+/).reject(&:empty?)
            if codes.length > 1
              unless change.sup? && codes.all? { |candidate| candidate.match?(/\A[A-Z]{4}\z/) }
                raise "F32 grouped office codes are only supported for SUP: OB #{change.ob_issue_no} #{code.inspect}"
              end

              @amendment_contexts << amendment_context(change, entry, index, codes,
                kind: 'aggregated-office-action')
              seed_by_code = publication.allocations.to_h { |seed_entry| [seed_entry.office_code, seed_entry] }
              next codes.map do |candidate|
                seed_entry = seed_by_code[candidate]
                raise "F32 grouped SUP code #{candidate.inspect} is absent from verified OB 980" unless seed_entry

                seed_entry.to_hash
              end
            end

            if code.start_with?('--')
              scope = Array(entry.network_codes)
              if scope.length == 1 && scope.first.match?(/\A[A-Z]{2}\z/)
                entry.office_code = scope.first + code.delete_prefix('--')
              else
                @amendment_contexts << amendment_context(change, entry, index, scope,
                  kind: 'network-relative-office')
                next []
              end
            end
            [entry.to_hash]
          end
          if offices.empty?
            @context_only_changes << change
            @context_only_sources << { change: change, path: @loaded_path }
            next
          end
          normalized = data.merge('entries' => offices)
          yield Change.from_hash(change.to_hash.merge('data' => normalized))
        end
      end

      def amendment_context(change, entry, index, scope, kind: 'network-relative-office')
        Models::F32SeedContext.new(
          kind: kind, ob_issue_no: change.ob_issue_no, entry: entry,
          network_codes: scope, related_office_code: entry.office_code,
          source_uri: "itu-ob-data/issues/#{change.ob_issue_no}/amendments.yaml",
          source_path: File.join('datasets/980-F.32/changes', File.basename(@loaded_path)),
          source_row: index + 1,
          explanation: 'The printed office suffix has no uniquely asserted network prefix; retained as edition context.'
        )
      end

      def seed_change
        return super if legacy_seed?

        Change.new(
          type: "SEED", register_id: @register_id,
          identifier: { "code" => "__seed__" },
          data: publication.allocations.map(&:to_hash), ob_issue_no: seed_issue
        )
      end

      def validate_publication!
        raise "F32 publication has not passed independent allocation completeness verification" unless publication.source_complete
        raise "F32 publication has no printed source fingerprint" unless publication.source_sha256.to_s.match?(/\A[0-9a-f]{64}\z/)
        expected = Digest::SHA256.file(File.join(seed_path, SEED_FILENAME)).hexdigest
        raise "F32 publication does not match the preserved legacy seed" unless publication.seed_sha256 == expected
        rules = Ituob::Support::Yaml.safe_load_file(Models::F32SeedBuilder::RULES_PATH)
        unless publication.source_sha256 == rules.fetch("source_sha256") &&
            publication.pages.map(&:number) == (1..rules.fetch("source_pages")).to_a
          raise "F32 publication does not cover the pinned official printed source"
        end
        original = Ituob::Support::Yaml.safe_load_file(File.join(seed_path, SEED_FILENAME)).map do |row|
          Models::F32TDIEntry.from_hash(row).to_yaml
        end
        unless publication.legacy_rows.map(&:to_yaml) == original
          raise "F32 publication does not retain every original legacy seed row"
        end

        raise "F32 publication has no office allocations" if publication.allocations.empty?
        keys = publication.allocations.map do |entry|
          raise "F32 publication contains a non-office allocation" unless entry.office_code.to_s.match?(/\A[A-Z]{4}\z/)
          key = entry.office_code
          raise "F32 publication contains an allocation without a country" if entry.country_or_area.nil?
          key
        end
        raise "F32 publication contains duplicate allocation identities" unless keys.uniq == keys
        publication.contexts.each do |context|
          unless CONTEXT_KINDS.include?(context.kind) && context.entry && context.source_row.to_i.positive? && context.source_uri
            raise "F32 publication has an invalid or untraceable context record"
          end
        end
      end
    end
  end
end
