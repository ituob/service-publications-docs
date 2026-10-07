# frozen_string_literal: true

module Ituob
  module Domain
    # A future-dated issue in the planned schedule.
    #
    # Each entry is a triple: issue number, publication date, cutoff date.
    PlannedIssue = Struct.new(:issue_id, :publication_date, :cutoff_date,
                              keyword_init: true) do
      def initialize(*args)
        super
        freeze
      end
    end

    # The forward publication schedule that ITU publishes alongside each
    # OB issue. Lists the next ~25 issue dates.
    #
    # Source: each issue's general.yaml carries a "planned_issues" array
    # populated by the build pipeline from prior issues' meta.yaml.
    # Additionally, the source itu-ob-data/defaults/issue/meta.yaml
    # contains the canonical schedule template.
    class PlannedIssuesSchedule
      attr_reader :entries

      def initialize(entries:)
        @entries = Array(entries).freeze
        freeze
      end

      # Build from the "planned_issues" array found in a source general.yaml.
      def self.from_planned_issues_array(array)
        return new(entries: []) unless array.is_a?(Array)

        entries = array.map do |entry|
          PlannedIssue.new(
            issue_id: entry['id']&.to_i,
            publication_date: parse_date(entry['publication_date']),
            cutoff_date: parse_date(entry['cutoff_date']),
          )
        end
        new(entries: entries)
      end

      # Build from the defaults/issue/meta.yaml template (the canonical
      # future schedule ITU publishes).
      def self.from_defaults_meta(meta_hash)
        return new(entries: []) unless meta_hash.is_a?(Hash)

        raw = meta_hash['planned_issues'] || meta_hash.dig('issue', 'planned_issues')
        from_planned_issues_array(raw)
      end

      # Return entries with publication_date strictly after +as_of+.
      def upcoming(as_of: Date.today)
        entries.select { |e| e.publication_date && e.publication_date > as_of }
      end

      # Return the next +n+ issues from +as_of+.
      def next_n(n, as_of: Date.today)
        upcoming(as_of: as_of).first(n)
      end

      def self.parse_date(value)
        return value if value.is_a?(Date)

        return nil unless value.is_a?(String)

        begin
          Date.iso8601(value)
        rescue ArgumentError
          nil
        end
      end

      private_class_method :parse_date
    end
  end
end

require 'date'
