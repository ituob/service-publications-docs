# frozen_string_literal: true

require 'json'
require 'fileutils'

module Ituob
  module Registers
    # Writes a register's full set of point-in-time snapshots to disk
    # in the wire format consumed by the Astro site.
    #
    # Encapsulates the FileUtils.mkdir_p + JSON.pretty_generate calls
    # previously inlined in +scripts/generate_register_snapshots.rb+.
    # The script becomes thin orchestration: build a Replay, hand the
    # resulting states to SnapshotWriter.
    #
    # Files written per register:
    #   {output_root}/{slug}/manifest.json
    #   {output_root}/{slug}/current.json
    #   {output_root}/{slug}/at-{N}.json   (one per touched OB issue)
    class SnapshotWriter
      include Ituob::Support::HashField

      attr_reader :output_root

      def initialize(output_root:)
        @output_root = output_root
      end

      # Write snapshots for one register.
      #
      # Inputs:
      # * +slug+ — filesystem slug used in the URL and directory name.
      # * +manifest_fields+ — Hash with register_id, recommendation,
      #   title, key_field, seed_issue (any extra fields are ignored).
      # * +current_state+ — State to serialize as current.json.
      # * +states_by_issue+ — Hash { ob_issue => State } for each
      #   touched OB issue. The issue keys become the +at-{N}.json+
      #   filenames.
      #
      # Returns the number of files written.
      def write(slug:, manifest_fields:, current_state:, states_by_issue:)
        dir = File.join(@output_root, slug)
        FileUtils.mkdir_p(dir)

        write_current(dir, slug, current_state)
        written = 1
        states_by_issue.each do |issue, state|
          next if issue.nil?

          write_at(dir, slug, issue, state)
          written += 1
        end
        write_manifest(dir, slug, manifest_fields, states_by_issue.keys)
        written + 1 # +1 for the manifest
      end

      private

      def write_current(dir, slug, state)
        File.write(
          File.join(dir, 'current.json'),
          JSON.pretty_generate(state.to_snapshot(slug: slug)),
        )
      end

      def write_at(dir, slug, issue, state)
        File.write(
          File.join(dir, "at-#{issue}.json"),
          JSON.pretty_generate(state.to_snapshot(slug: slug)),
        )
      end

      def write_manifest(dir, slug, fields, touched_issues)
        manifest = {
          'slug' => slug,
          'register_id' => lookup(fields, :register_id),
          'recommendation' => lookup(fields, :recommendation),
          'title' => lookup(fields, :title),
          'key_field' => lookup(fields, :key_field),
          'seed_issue' => lookup(fields, :seed_issue),
          'touched_issues' => touched_issues.compact.sort,
        }
        File.write(
          File.join(dir, 'manifest.json'),
          JSON.pretty_generate(manifest),
        )
      end
    end
  end
end
