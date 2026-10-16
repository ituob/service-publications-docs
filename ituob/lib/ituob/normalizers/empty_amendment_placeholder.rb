# frozen_string_literal: true

require 'fileutils'

module Ituob
  module Normalizers
    # Write a +placeholder.yaml+ for every (issue × slug) pair whose source
    # YAML declares an amendment with empty +contents+.
    #
    # This completes the structure: every declared amendment has a file
    # in +ob-issues/{id}/{slug}+, even if the source published nothing.
    class EmptyAmendmentPlaceholder < Base
      def apply_to(issue_id)
        result = Result.new(name: name)
        source = issue_repository.read_amendments(issue_id)
        return result unless source.is_a?(Hash) && source['messages'].is_a?(Array)

        source['messages'].each do |msg|
          next unless msg['type'] == 'amendment'

          publication = msg.dig('target', 'publication')
          next unless publication

          contents = msg['contents']
          # Treat as empty when: contents is nil, {}, or a hash whose
          # only value is also empty (e.g. +contents: {en: {}}+).
          is_empty = contents.nil? ||
                     contents == {} ||
                     (contents.is_a?(Hash) && contents.values.all? { |v| v.nil? || v == {} })
          next unless is_empty

          slug = Catalogs::Publications.slug_for(publication)
          dir = File.join(issue_repository.output_root, issue_id.to_s, slug)
          next if Dir.exist?(dir) && !Dir.children(dir).grep(/\.yaml\z/).empty?

          FileUtils.mkdir_p(dir)
          placeholder = {
            '_class' => 'EmptyAmendment',
            'ob_issue_no' => issue_id.to_s,
            'reference' => "OB-#{issue_id}",
            'publication' => publication,
            'target' => msg['target'],
            'note' => 'Amendment declared in source with contents: {} — no content published for this issue',
          }
          issue_repository.write_change_object(issue_id, slug, 'placeholder.yaml', placeholder)
          result.files_created += 1
          result.issues_affected += 1
        end
        result
      end
    end
  end
end
