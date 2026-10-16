# frozen_string_literal: true

require 'json'
require 'fileutils'

module Ituob
  module Verifiers
    # Verifies that generated register snapshots are consistent with
    # the catalog and contain real data when a seed is expected.
    #
    # +CatalogIntegrityVerifier+ checks the catalog against seed data
    # on disk. +SnapshotIntegrityVerifier+ checks the *generated
    # artifacts* (JSON snapshots under ituob.org-v2/data/snapshots/)
    # against the catalog. Together they guard the snapshot pipeline
    # end-to-end.
    #
    # Failure modes reported:
    #   * snapshots/{slug}/manifest.json missing
    #   * manifest.key_field != catalog.key_field
    #   * manifest.seed_issue != catalog.seed_issue
    #   * manifest.register_id != catalog.register_id
    #   * manifest.recommendation != catalog.recommendation
    #   * current.json#entry_count == 0 despite the catalog declaring a seed
    class SnapshotIntegrityVerifier < Base
      attr_reader :registers_catalog, :snapshots_root

      def initialize(registers_catalog: Ituob::Catalogs::Registers,
                     snapshots_root: default_snapshots_root)
        super()
        @registers_catalog = registers_catalog
        @snapshots_root = snapshots_root
      end

      def verify
        result = Result.new(name: name)

        @registers_catalog.each_entry do |reg|
          next if reg.external?
          next unless reg.seed_path

          verify_register(reg, result)
        end
        result
      end

      private

      def verify_register(reg, result)
        slug_dir = File.join(@snapshots_root, reg.slug)
        manifest_path = File.join(slug_dir, 'manifest.json')
        current_path = File.join(slug_dir, 'current.json')

        unless File.file?(manifest_path)
          result.errors << "#{reg.register_id}: missing manifest at #{manifest_path}"
          return
        end

        manifest = load_json(manifest_path, result, reg.register_id)
        return unless manifest

        check_field(result, reg, manifest, 'key_field', reg.key_field)
        check_field(result, reg, manifest, 'seed_issue', reg.seed_issue)
        check_field(result, reg, manifest, 'register_id', reg.register_id)
        check_field(result, reg, manifest, 'recommendation', reg.recommendation)

        check_current_entries(result, reg, current_path)
      end

      def check_field(result, reg, manifest, field, expected)
        actual = manifest[field]
        return if actual == expected

        result.errors << format_mismatch(reg, field, expected, actual)
      end

      def check_current_entries(result, reg, current_path)
        return unless File.file?(current_path)

        current = load_json(current_path, result, reg.register_id)
        return unless current

        count = current['entry_count']
        return unless count.is_a?(Integer) && count.zero?

        result.warnings << "#{reg.register_id}: current.json has 0 active entries despite catalog declaring seed #{reg.seed_issue.inspect}"
      end

      def format_mismatch(reg, field, expected, actual)
        "#{reg.register_id}: manifest.#{field} mismatch — catalog=#{expected.inspect}, snapshot=#{actual.inspect}"
      end

      def load_json(path, result, register_id)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        result.errors << "#{register_id}: invalid JSON at #{path} (#{e.message})"
        nil
      end

      def default_snapshots_root
        File.expand_path('../../../../ituob.org-v2/data/snapshots', __dir__)
      end
    end
  end
end
