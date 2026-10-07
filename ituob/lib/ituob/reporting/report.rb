# frozen_string_literal: true

require 'yaml'

module Ituob
  module Reporting
    # Aggregate verification results into a single report.
    class Report
      attr_reader :results

      def initialize(results = [])
        @results = Array(results)
      end

      def add(result)
        @results << result
        self
      end

      # Render as YAML for machine consumption.
      def to_yaml
        payload = {
          'generated_at' => Time.now.utc.iso8601,
          'results' => @results.map { |r| serialize_result(r) },
        }
        YAML.dump(payload).sub(/\A---\n/, '')
      end

      # Render as plain-text stdout summary.
      def to_summary
        lines = []
        @results.each do |r|
          lines << format('%-30s errors=%-4d warnings=%-4d %s',
                          r.name, r.errors.length, r.warnings.length,
                          r.stats.inspect)
          r.errors.first(5).each { |e| lines << "  ERROR: #{e}" }
          r.warnings.first(3).each { |w| lines << "  WARN:  #{w}" }
        end
        lines.join("\n")
      end

      def write_yaml(path)
        File.write(path, to_yaml, encoding: 'utf-8')
      end

      def write_summary(io = $stdout)
        io.puts to_summary
      end

      private

      def serialize_result(result)
        {
          'name' => result.name,
          'errors' => result.errors,
          'warnings' => result.warnings,
          'stats' => serialize_stats(result.stats),
          'details' => result.details,
        }
      end

      def serialize_stats(stats)
        stats.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? v : (v.is_a?(Struct) ? v.to_h : v)
        end
      end
    end
  end
end

require 'time'
