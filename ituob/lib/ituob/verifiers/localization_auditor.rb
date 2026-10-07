# frozen_string_literal: true

module Ituob
  module Verifiers
    # Reports per-language coverage of localized fields across all datasets.
    class LocalizationAuditor < Base
      REQUIRED = %w[en fr es].freeze
      OPTIONAL = %w[ru zh ar].freeze
      ALL = (REQUIRED + OPTIONAL).freeze

      def initialize(dataset_repository:)
        super()
        @dataset_repository = dataset_repository
      end

      def verify
        result = Result.new(name: name)
        result.stats[:total_fields] = 0
        result.stats[:full_coverage] = 0
        result.stats[:missing_required] = 0

        @dataset_repository.each_slug do |slug|
          data = @dataset_repository.read_data(slug)
          next unless data

          walk(data) do |fields|
            result.stats[:total_fields] += 1
            langs = fields.keys.map(&:to_s)
            if (REQUIRED - langs).empty?
              result.stats[:full_coverage] += 1
            else
              result.stats[:missing_required] += (REQUIRED - langs).length
            end
          end
        end

        coverage_pct = if result.stats[:total_fields].positive?
                         (100.0 * result.stats[:full_coverage] / result.stats[:total_fields]).round(2)
                       else
                         100.0
                       end
        result.stats[:coverage_pct] = coverage_pct
        result.warnings << "Coverage: #{coverage_pct}% of #{result.stats[:total_fields]} fields" if coverage_pct < 99.0
        result
      end

      private

      def walk(node, &block)
        case node
        when Hash
          if node.keys.any? { |k| ALL.include?(k.to_s) }
            yield node
          else
            node.each_value { |v| walk(v, &block) }
          end
        when Array
          node.each { |v| walk(v, &block) }
        end
      end
    end
  end
end
