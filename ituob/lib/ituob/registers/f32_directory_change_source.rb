# frozen_string_literal: true

require "digest"
require "ituob/models"

module Ituob
  module Registers
    # Reads the explicitly verified F.32 publication while retaining its context.
    # The artifact is mandatory: the unverified legacy seed is never a fallback.
    class F32DirectoryChangeSource < DirectoryChangeSource
      PUBLICATION_FILENAME = "publication.yaml"
      CONTEXT_KINDS = %w[printed-row heading network reservation telex alias continuation printed-unassigned shared-indicator network-relative-office aggregated-office-action].freeze

      attr_reader :publication, :context_only_changes, :context_only_sources

      def initialize(**options)
        super
        @amendment_contexts = []
        @context_only_changes = []
        @context_only_sources = []
        return unless @register_id == "F32_TDI"

        @publication = load_publication
        validate_publication!
      end

      # Context is a first-class edition input, including context-only actions.
      # Canonical event files remain the durable source for these later records.
      def contexts_at_issue(issue = nil)
        each_sorted { |_change| nil }
        (publication.contexts + @amendment_contexts).select do |context|
          issue.nil? || context.ob_issue_no.to_i <= issue.to_i
        end
      end

      private

      def publication_path
        File.join(seed_path, PUBLICATION_FILENAME)
      end

      def load_publication
        unless File.file?(publication_path)
          raise "F32 publication #{publication_path} is missing; the unverified legacy data.yaml is not a " \
                "fallback. Restore it or regenerate it with scripts/build_f32_seed_publication.rb"
        end
        Models::F32SeedPublication.from_yaml(File.read(publication_path))
      rescue Lutaml::Model::Error => e
        raise "F32 publication #{publication_path} is unreadable (#{e.class}); regenerate it with " \
              "scripts/build_f32_seed_publication.rb"
      end

      def each_amendment
        return enum_for(:each_amendment) unless block_given?
        @amendment_contexts = []
        @context_only_changes = []
        @context_only_sources = []
        @network_offices = seed_network_offices
        emit = proc { |emitted| track_network_offices(emitted); register_path(emitted); yield emitted }
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
            reject_empty_network_replacement!(change)
            emit.call(change)
            next
          end
          printed_codes = {}
          offices = rows.each_with_index.flat_map do |row, index|
            entry = Models::F32TDIEntry.from_hash(row)
            code = entry.office_code.to_s.strip
            if code.match?(/\A[A-Z]{4}\z/) && printed_codes[code]
              @amendment_contexts << amendment_context(change, entry, index, Array(entry.network_codes),
                kind: 'shared-indicator',
                explanation: 'Another printed office served by a destination indicator already carried by this amendment.')
              next []
            end
            printed_codes[code] = true
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
            reject_empty_network_replacement!(change)
            @context_only_changes << change
            @context_only_sources << { change: change, path: @loaded_path }
            next
          end
          normalized = data.merge('entries' => offices)
          replaced_network_changes(change, offices).each { |removal| emit.call(removal) }
          emit.call(Change.from_hash(change.to_hash.merge('data' => normalized)))
        end
      end

      # A REP carrying `replaces_network: true` replaces its network's whole
      # printed list: every office the register holds on that network at this
      # issue (seed and earlier amendments) that the REP does not print is
      # withdrawn. The source tracks that state as it streams the changes.
      def replaced_network_changes(change, offices)
        return [] unless replaces_network?(change)

        kept = offices.map { |office| office['office_code'] }
        networks = offices.filter_map { |office| network_prefix(office) }.uniq
        raise "F32 change #{@loaded_path} sets replaces_network but prints no network" if networks.empty?

        stale = networks.flat_map { |network| @network_offices.fetch(network, {}).values }
                        .reject { |office| kept.include?(office['office_code']) }
        return [] if stale.empty?

        [Change.new(type: 'SUP', register_id: @register_id, ob_issue_no: change.ob_issue_no,
                    identifier: { 'code' => stale.first['office_code'] },
                    data: { 'entries' => stale })]
      end

      def replaces_network?(change)
        flag = change.data['replaces_network']
        return false if flag.nil? || flag == false
        raise "F32 change #{@loaded_path} has a non-boolean replaces_network" unless flag == true
        raise "F32 change #{@loaded_path} sets replaces_network on a #{change.type}, not a REP" unless change.type == 'REP'

        true
      end

      def reject_empty_network_replacement!(change)
        return unless change.data.is_a?(Hash) && change.data.key?('replaces_network')

        raise "F32 change #{@loaded_path} sets replaces_network but has no entries"
      end

      def seed_network_offices
        publication.allocations.each_with_object({}) do |seed_entry, networks|
          office = seed_entry.to_hash
          (networks[network_prefix(office)] ||= {})[office['office_code']] = office
        end
      end

      # An office lives on one network at a time: a later ADD, REP or MOD
      # that moves it takes it off its old network, and SUP or DEL drops it.
      def track_network_offices(change)
        entries = change.data.is_a?(Hash) ? Array(change.data['entries']) : []
        case change.type
        when 'ADD', 'REP'
          entries.each { |office| file_office(office) }
        when 'MOD'
          entries.each do |patch|
            current = forget_office(patch['office_code'])
            file_office(current ? current.merge(patch) : patch)
          end
        when 'SUP', 'DEL'
          codes = entries.empty? ? [change.identifier.code] : entries.map { |office| office['office_code'] }
          codes.each { |code| forget_office(code) }
        end
      end

      def file_office(office)
        forget_office(office['office_code'])
        (@network_offices[network_prefix(office)] ||= {})[office['office_code']] = office
      end

      def forget_office(code)
        @network_offices.each_value.filter_map { |offices| offices.delete(code) }.first
      end

      def network_prefix(office)
        office['network_code'].to_s[/\A[A-Z]{2}/]
      end

      def amendment_context(change, entry, index, scope, kind: 'network-relative-office',
                            explanation: 'The printed office suffix has no uniquely asserted network prefix; retained as edition context.')
        Models::F32SeedContext.new(
          kind: kind, ob_issue_no: change.ob_issue_no, entry: entry,
          network_codes: scope, related_office_code: entry.office_code,
          source_uri: "itu-ob-data/issues/#{change.ob_issue_no}/amendments.yaml",
          source_path: File.join('datasets/980-F.32/changes', File.basename(@loaded_path)),
          source_row: index + 1,
          explanation: explanation
        )
      end

      def seed_change
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
