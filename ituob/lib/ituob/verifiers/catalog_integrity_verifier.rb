# frozen_string_literal: true

require 'set'

module Ituob
  module Verifiers
    # Cross-checks the catalogs for internal consistency:
    #
    # * Every register's +recommendation+ exists in recommendations.yaml.
    # * Every non-external register's +seed_path+ exists on disk.
    # * Every register's +key_field+ appears in the seed data's keys.
    #
    # Produces a verification result listing orphan references and
    # missing directories.
    class CatalogIntegrityVerifier < Base
      attr_reader :registers_catalog, :recommendations_catalog, :root

      def initialize(registers_catalog: Ituob::Catalogs::Registers,
                     recommendations_catalog: Ituob::Catalogs::Recommendations,
                     root: default_root)
        super()
        @registers_catalog = registers_catalog
        @recommendations_catalog = recommendations_catalog
        @root = root
      end

      def verify
        result = Result.new(name: name)
        result.stats[:registers_checked] = 0
        result.stats[:recommendations_checked] = 0

        rec_codes = Set.new
        @recommendations_catalog.each { |r| rec_codes << r.code }
        result.stats[:recommendations_checked] = rec_codes.length

        @registers_catalog.each_entry do |reg|
          result.stats[:registers_checked] += 1

          check_recommendation(reg, rec_codes, result)
          check_seed_path(reg, result) unless reg.external?
          check_key_field(reg, result) unless reg.external?
        end

        result
      end

      private

      def check_recommendation(reg, rec_codes, result)
        return if rec_codes.include?(reg.recommendation)

        result.errors <<
          "#{reg.register_id}: recommendation #{reg.recommendation.inspect} not in recommendations.yaml"
      end

      def check_seed_path(reg, result)
        return unless reg.seed_path

        full = File.expand_path(reg.seed_path, @root)
        return if Dir.exist?(full)

        result.errors <<
          "#{reg.register_id}: seed_path #{reg.seed_path.inspect} does not exist (resolved: #{full})"
      end

      def check_key_field(reg, result)
        return unless reg.seed_path && reg.key_field

        data_path = File.expand_path(File.join(reg.seed_path, 'data.yaml'), @root)
        return unless File.file?(data_path)

        data = Ituob::Support::Yaml.safe_load_file(data_path)
        return unless data.is_a?(Array) && data.first.is_a?(Hash)

        sample_keys = data.first.keys.map(&:to_s)
        return if sample_keys.include?(reg.key_field)

        result.warnings <<
          "#{reg.register_id}: key_field #{reg.key_field.inspect} not found in seed data keys #{sample_keys.inspect}"
      end

      def default_root
        File.expand_path('../../../..', __dir__)
      end
    end
  end
end
