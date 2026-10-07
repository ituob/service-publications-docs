# frozen_string_literal: true

module Ituob
  module Verifiers
    # Detect the char-exploded YAML serialization bug.
    #
    # Some source YAML files have a +contents:+ field that was supposed
    # to be a String path (e.g. +"amendments/foo.adoc"+) but got
    # serialized as a per-character-indexed Hash. This verifier detects
    # that corruption pattern.
    class CharExplodedDetector < Base
      VALUE_LINE = /^      '[0-9]+': (.+)$/.freeze

      def verify
        result = Result.new(name: name)
        result.stats[:affected_issues] = 0
        result.stats[:corrupted_fields] = 0

        issue_repository.each_source_issue_id do |iid|
          findings = []
          %w[amendments.yaml general.yaml].each do |fname|
            path = File.join(issue_repository.source_root, iid.to_s, fname)
            next unless File.file?(path)

            findings.concat(scan_file(path))
          end
          next if findings.empty?

          result.stats[:affected_issues] += 1
          result.stats[:corrupted_fields] += findings.length
          result.errors << "OB #{iid}: #{findings.length} char-exploded fields"
        end
        result
      end

      private

      def scan_file(path)
        findings = []
        lines = File.readlines(path, encoding: 'utf-8').map(&:chomp)

        i = 0
        while i < lines.length
          if lines[i].strip == 'contents:'
            chars, last_idx = collect_exploded(lines, i + 1)
            if chars.length > 5
              findings << { line: i + 1, reconstructed: chars.join }
              i = last_idx + 1
            else
              i += 1
            end
          else
            i += 1
          end
        end
        findings
      end

      def collect_exploded(lines, start_idx)
        chars = []
        idx = start_idx
        base_indent = nil
        while idx < lines.length
          line = lines[idx]
          m = VALUE_LINE.match(line)
          return chars, idx - 1 unless m

          indent_match = line.match(/^(\s*)'/)
          indent = indent_match ? indent_match[1] : ''
          base_indent ||= indent
          return chars, idx - 1 if indent != base_indent

          raw = m[1]
          raw = raw[1..-2] if raw.length >= 2 && raw.start_with?("'") && raw.end_with?("'")
          return chars, idx - 1 unless raw.length == 1

          position = line.match(/'([0-9]+)':/)[1].to_i
          return chars, idx - 1 if position != chars.length

          chars << raw
          idx += 1
        end
        [chars, idx - 1]
      end
    end
  end
end
