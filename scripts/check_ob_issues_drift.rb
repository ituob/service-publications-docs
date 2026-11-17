#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Compare the checked issue files with a disposable regeneration. The real
# builder remains the only implementation of the source-to-output mapping.
class ObIssuesDriftCheck
  def initialize(data_root:, output_root:, issue_ids: nil)
    @data_root = File.expand_path(data_root)
    @output_root = File.expand_path(output_root)
    @issue_ids = issue_ids
  end

  def run
    source = File.join(@data_root, 'issues')
    raise ArgumentError, "Source issues directory missing: #{source}" unless Dir.exist?(source)

    ids = selected_ids(source)
    Dir.mktmpdir('ob-issues-drift') do |temporary|
      regenerate(temporary, ids)
      report(compare(temporary, ids), ids.size)
    end
  end

  private

  def report(differences, count)
    if differences.empty?
      puts "No ob-issues drift (#{count} issues)"
    else
      puts 'ob-issues drift detected:'
      differences.each { |difference| puts difference }
    end
    differences.empty?
  end

  def selected_ids(source)
    available = numeric_directories(source) | numeric_directories(@output_root)
    return available.sort_by(&:to_i) if @issue_ids.to_s.strip.empty?

    ids = parsed_ids
    unknown = ids - available
    raise ArgumentError, "Unknown issue IDs: #{unknown.join(',')}" unless unknown.empty?

    ids.uniq.sort_by(&:to_i)
  end

  def parsed_ids
    ids = @issue_ids.split(',', -1).map(&:strip)
    unless ids.all? { |id| id.match?(/\A\d+\z/) }
      raise ArgumentError, 'ISSUE_IDS must contain comma-separated numeric issue IDs'
    end

    ids
  end

  def numeric_directories(root)
    return [] unless Dir.exist?(root)

    Dir.children(root).select do |name|
      name.match?(/\A\d+\z/) && File.directory?(File.join(root, name))
    end
  end

  def build_environment(temporary, ids)
    {
      'ITU_OB_DATA_ROOT' => @data_root,
      'OB_ISSUES_OUT_PATH' => temporary,
      # A partial build suppresses the volatile manifest and coverage reports.
      'ISSUE_IDS' => ids.join(','),
      'ISSUE_SAMPLE' => nil,
      'CUTOVER_EDITION' => nil
    }
  end

  def regenerate(temporary, ids)
    stdout, stderr, status = Open3.capture3(
      build_environment(temporary, ids), RbConfig.ruby, File.join(__dir__, 'build_ob_issues.rb')
    )
    # The builder currently rescues per-issue errors without a nonzero exit.
    return if status.success? && !stderr.match?(/^FAIL /)

    raise "Regeneration failed:\n#{stdout}#{stderr}"
  end

  def compare(generated_root, ids)
    (files(generated_root, ids) | files(@output_root, ids)).sort.filter_map do |path|
      difference(path, generated_root)
    end
  end

  def difference(path, generated_root)
    expected = File.join(generated_root, path)
    checked = File.join(@output_root, path)
    return "missing: #{path}" unless File.file?(checked)
    return "extra: #{path}" unless File.file?(expected)

    "changed: #{path}" unless FileUtils.compare_file(expected, checked)
  end

  def files(root, ids)
    ids.flat_map do |id|
      Dir.glob("#{id}/**/*", File::FNM_DOTMATCH, base: root).select do |relative|
        File.file?(File.join(root, relative))
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    check = ObIssuesDriftCheck.new(
      data_root: ENV.fetch('ITU_OB_DATA_ROOT', File.expand_path('../itu-ob-data', __dir__)),
      output_root: ENV.fetch('OB_ISSUES_OUT_PATH', File.expand_path('../ob-issues', __dir__)),
      issue_ids: ENV['ISSUE_IDS']
    )
    exit(check.run ? 0 : 1)
  rescue ArgumentError, RuntimeError, SystemCallError => e
    warn e.message
    exit 1
  end
end
