# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

RSpec.describe 'scripts/check_ob_issues_drift.rb' do # rubocop:disable Metrics/BlockLength -- Integration examples share an isolated fixture tree.
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:environment) do
    {
      'ITU_OB_DATA_ROOT' => @data,
      'OB_ISSUES_OUT_PATH' => @output,
      'ISSUE_IDS' => '10,11',
      'ISSUE_SAMPLE' => nil,
      'CUTOVER_EDITION' => nil
    }
  end
  let(:result) do
    Open3.capture3(environment, RbConfig.ruby,
                   File.join(repo_root, 'scripts/check_ob_issues_drift.rb'))
  end

  around do |example|
    Dir.mktmpdir('ob-drift-spec') do |dir|
      @data = File.join(dir, 'itu-ob-data')
      @output = File.join(dir, 'ob-issues')
      %w[10 11].each do |id|
        source = File.join(@data, 'issues', id)
        FileUtils.mkdir_p(source)
        File.write(File.join(source, 'meta.yaml'), "id: #{id}\ndate: 2020-01-01\n")
        File.write(File.join(source, 'general.yaml'), <<~YAML)
          messages:
          - type: custom
            title: message #{id}
        YAML
      end
      stdout, stderr, status = Open3.capture3(
        environment, RbConfig.ruby, File.join(repo_root, 'scripts/build_ob_issues.rb')
      )
      expect(status.success?).to be(true), stdout + stderr
      example.run
    end
  end

  it 'passes a clean regeneration without changing the checked tree or writing reports' do
    environment['ISSUE_IDS'] = ''
    File.write(File.join(@output, 'manifest.yaml'), 'volatile report')
    before = Dir.glob("#{@output}/**/*").select { |path| File.file?(path) }
                .to_h { |path| [path, File.binread(path)] }
    stdout, stderr, status = result
    expect(status.success?).to be(true), stdout + stderr
    expect(stdout).to include('No ob-issues drift (2 issues)')
    expect(before).to all(satisfy { |path, contents| File.binread(path) == contents })
    expect(Dir.glob("#{@output}/**/*").select { |path| File.file?(path) }).to eq(before.keys)
  end

  it 'detects a hand-edited generated file even with inherited build limits' do
    path = File.join(@output, '11/custom/001.yaml')
    File.write(path, "hand edited\n")
    environment.merge!('CUTOVER_EDITION' => '1', 'ISSUE_SAMPLE' => '0')
    stdout, _stderr, status = result
    expect(status.success?).to be(false)
    expect(stdout).to include('changed: 11/custom/001.yaml')
    expect(File.read(path)).to eq("hand edited\n")
  end

  it 'reports missing and extra files, including a removed source issue' do
    environment['ISSUE_IDS'] = nil
    FileUtils.rm(File.join(@output, '10/meta.yaml'))
    FileUtils.mkdir_p(File.join(@output, '12'))
    File.write(File.join(@output, '12/meta.yaml'), 'stale')
    stdout, _stderr, status = result
    expect(status.success?).to be(false)
    expect(stdout).to include('missing: 10/meta.yaml', 'extra: 12/meta.yaml')
  end

  it 'limits comparison to explicitly selected issues' do
    environment['ISSUE_IDS'] = ' 10 '
    File.write(File.join(@output, '11/meta.yaml'), 'outside scope')
    stdout, stderr, status = result
    expect(status.success?).to be(true), stdout + stderr
    expect(stdout).to include('No ob-issues drift (1 issues)')
  end

  it 'rejects invalid issue selections rather than silently checking nothing' do
    environment['ISSUE_IDS'] = '10,typo'
    _stdout, stderr, status = result
    expect(status.success?).to be(false)
    expect(stderr).to include('ISSUE_IDS must contain comma-separated numeric issue IDs')
  end

  it 'fails when the source checkout is missing' do
    FileUtils.rm_rf(@data)
    _stdout, stderr, status = result
    expect(status.success?).to be(false)
    expect(stderr).to include('Source issues directory missing')
  end

  it 'rejects unknown numeric IDs rather than silently checking nothing' do
    environment['ISSUE_IDS'] = '999'
    _stdout, stderr, status = result
    expect(status.success?).to be(false)
    expect(stderr).to include('Unknown issue IDs: 999')
  end

  it 'fails if the builder reports a per-issue failure despite exiting successfully' do
    File.write(File.join(@data, 'issues/10/general.yaml'), "messages: [\n")
    _stdout, stderr, status = result
    expect(status.success?).to be(false)
    expect(stderr).to include('Regeneration failed', 'FAIL 10:')
  end
end

RSpec.describe 'documented itu-ob-data caller contract' do
  let(:documentation) do
    File.read(File.expand_path('../../../docs/normalization/source-of-truth.adoc', __dir__))
  end
  let(:caller_job) do
    example = documentation.match(/\[source,yaml\]\n----\n(jobs:.*?)\n----/m)[1]
    YAML.safe_load(example).fetch('jobs').fetch('validate')
  end

  it 'calls the agreed reusable workflow on main' do
    expect(caller_job.fetch('uses')).to eq(
      'ituob/service-publications-docs/.github/workflows/validate-itu-ob-data.yml@main'
    )
  end

  it 'passes exactly the four agreed inputs with the documented defaults' do
    expect(caller_job.fetch('with')).to eq(
      'itu_ob_data_ref' => '${{ github.event.pull_request.head.sha }}',
      'itu_ob_data_repository' => 'ituob/itu-ob-data',
      'issue_ids' => '',
      'base_ref' => 'main'
    )
  end

  it 'shows how to pass the optional private-checkout token' do
    expect(caller_job.fetch('secrets', {})).to eq(
      'ITU_OB_DATA_TOKEN' => '${{ secrets.ITU_OB_DATA_TOKEN }}'
    )
  end
end
