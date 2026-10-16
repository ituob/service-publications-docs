# frozen_string_literal: true

module Ituob
  module Verifiers
    # Comprehensive per-issue audit: every declared general message type
    # and every declared amendment has a matching output in ob-issues/.
    class PerIssueAuditor < Base
      def verify
        result = Result.new(name: name)
        result.stats[:issues_complete] = 0
        result.stats[:issues_incomplete] = 0
        result.stats[:issues_with_fallbacks] = 0
        result.stats[:fallbacks_total] = 0

        issue_repository.each_source_issue_id do |iid|
          report = audit_issue(iid)
          if report[:complete]
            result.stats[:issues_complete] += 1
          else
            result.stats[:issues_incomplete] += 1
            result.errors << "OB #{iid}: #{report[:gaps].join('; ')}" unless report[:gaps].empty?
          end
          unless report[:fallbacks].empty?
            result.stats[:issues_with_fallbacks] += 1
            result.stats[:fallbacks_total] += report[:fallbacks].length
          end
        end
        result
      end

      private

      def audit_issue(issue_id)
        gaps = []
        fallbacks = []

        check_general_types(issue_id, gaps)
        check_amendments(issue_id, gaps, fallbacks)

        { complete: gaps.empty?, gaps: gaps, fallbacks: fallbacks }
      end

      def check_general_types(issue_id, gaps)
        source = issue_repository.read_general(issue_id)
        return unless source.is_a?(Hash) && source['messages'].is_a?(Array)

        source_types = source['messages'].map { |m| m['type'] || Catalogs::MessageTypes::UNTYPED }.to_set
        output_root = issue_repository.output_root
        source_types.each do |t|
          case Catalogs::MessageTypes.category(t)
          when :structured
            gaps << "missing general/#{t}.yaml" unless File.exist?(File.join(output_root, issue_id.to_s, 'general', "#{t}.yaml"))
          when :textual
            dir = File.join(output_root, issue_id.to_s, t)
            gaps << "missing #{t}/*.yaml" unless Dir.exist?(dir) && !Dir.children(dir).grep(/\.yaml\z/).empty?
          end
        end
      end

      def check_amendments(issue_id, gaps, fallbacks)
        source = issue_repository.read_amendments(issue_id)
        return unless source.is_a?(Hash) && source['messages'].is_a?(Array)

        source['messages'].each do |msg|
          next unless msg['type'] == 'amendment'

          publication = msg.dig('target', 'publication')
          next unless publication

          slug = Catalogs::Publications.slug_for(publication)
          contents = msg['contents']
          empty = contents.nil? || contents == {} || (contents.is_a?(Hash) && contents.empty?)

          # Skip empty-content amendments: the source declared an
          # amendment with no payload (cancellation notice, deferred
          # publication). No output file is expected.
          next if empty

          dir = File.join(issue_repository.output_root, issue_id.to_s, slug)
          yaml_files = Dir.exist?(dir) ? Dir.children(dir).select { |n| n.end_with?('.yaml') } : []

          if yaml_files.empty?
            gaps << "#{publication} (#{slug}): no output files"
          elsif yaml_files == ['text.yaml'] && !Catalogs::Publications.textual?(publication)
            fallbacks << "#{publication} (#{slug})"
          end
        end
      end
    end
  end
end

require 'set'
