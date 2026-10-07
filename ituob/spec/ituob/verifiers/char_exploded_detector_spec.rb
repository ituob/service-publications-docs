# frozen_string_literal: true

require 'spec_helper'
require 'ituob/verifiers'
require 'tmpdir'

RSpec.describe Ituob::Verifiers::CharExplodedDetector do
  IssueRepo = Struct.new(:source_root, :issue_ids) do
    def each_source_issue_id
      issue_ids.each { |iid| yield iid }
    end
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:issue_dir) { File.join(tmpdir, '1001') }
  let(:repo) { IssueRepo.new(tmpdir, ['1001']) }
  let(:detector) { described_class.new(issue_repository: repo) }

  after { FileUtils.rm_rf(tmpdir) }

  def write_amendments(content)
    FileUtils.mkdir_p(issue_dir)
    File.write(File.join(issue_dir, 'amendments.yaml'), content)
  end

  it 'reports no errors for clean YAML' do
    write_amendments(<<~YAML)
      ---
      amendments:
        - publication: E.118
          contents: "path/to/file.adoc"
    YAML
    result = detector.verify
    expect(result.stats[:affected_issues]).to eq(0)
    expect(result.stats[:corrupted_fields]).to eq(0)
    expect(result.errors).to be_empty
  end

  it 'detects char-exploded contents field' do
    exploded = (0...10).map { |i| "      '#{i}': '#{(97 + i).chr}'" }.join("\n")
    write_amendments(<<~YAML)
      ---
      amendments:
        - publication: E.118
          contents:
      #{exploded}
    YAML
    result = detector.verify
    expect(result.stats[:affected_issues]).to eq(1)
    expect(result.stats[:corrupted_fields]).to eq(1)
    expect(result.errors.first).to include('OB 1001')
  end

  it 'ignores short char sequences (<6 chars)' do
    exploded = (0...4).map { |i| "      '#{i}': '#{(97 + i).chr}'" }.join("\n")
    write_amendments(<<~YAML)
      ---
      amendments:
        - publication: E.118
          contents:
      #{exploded}
    YAML
    result = detector.verify
    expect(result.stats[:corrupted_fields]).to eq(0)
  end

  it 'scans both amendments.yaml and general.yaml' do
    exploded = (0...8).map { |i| "      '#{i}': '#{(97 + i).chr}'" }.join("\n")
    FileUtils.mkdir_p(issue_dir)
    File.write(File.join(issue_dir, 'general.yaml'), "contents:\n#{exploded}\n")
    result = detector.verify
    expect(result.stats[:corrupted_fields]).to eq(1)
  end

  it 'handles missing files gracefully' do
    result = detector.verify
    expect(result.stats[:affected_issues]).to eq(0)
  end
end
