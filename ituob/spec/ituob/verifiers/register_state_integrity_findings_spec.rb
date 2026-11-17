# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'ituob/catalogs'
require 'ituob/registers'
require 'ituob/verifiers'
require_relative '../../support/register_integrity_findings'

# The gate replays real change files, so every corruption below is written as
# a change file on disk, exactly as a contributor would add it. A replay
# finding that is not in the reviewed allowlist must fail the gate.
RSpec.describe Ituob::Verifiers::RegisterStateIntegrityVerifier, 'replay findings' do
  include RegisterIntegrityFindings
  let(:root) { Dir.mktmpdir('register-state-integrity-findings') }
  let(:dataset) { File.join(root, 'datasets', '1000-Test') }
  let(:changes_dir) { File.join(dataset, 'changes') }
  let(:register) do
    Ituob::Catalogs::Registers::Entry.new(
      register_id: 'TEST', slug: 'test', key_field: 'code', seed_issue: 1000, seed_path: 'datasets/1000-Test'
    )
  end
  let(:catalog) do
    entries = [register]
    Object.new.tap { |object| object.define_singleton_method(:each_entry) { |&block| entries.each(&block) } }
  end
  let(:allowlist) { [] }
  let(:result) do
    described_class.new(registers_catalog: catalog, root: root, allowlist: allowlist).verify
  end

  before do
    FileUtils.mkdir_p(changes_dir)
    File.write(File.join(dataset, 'data.yaml'),
               [{ 'code' => 'AAA', 'country' => 'iso-3166:aa' }, { 'code' => 'BBB', 'country' => 'iso-3166:bb' }].to_yaml)
    # Replay reports skips on stderr as well; keep the spec output clean.
    allow_any_instance_of(Ituob::Registers::Replay).to receive(:warn)
    allow_any_instance_of(Ituob::Registers::DirectoryChangeSource).to receive(:warn)
  end
  after { FileUtils.rm_rf(root) }

  it 'passes a clean register with no findings' do
    write_change('1001-0001-ADD-CCC.yaml', change('ADD', 'CCC', data: { 'code' => 'CCC', 'country' => 'iso-3166:cc' }))

    expect(result).to be_passed
    expect(result.stats).to include(replay_findings: 0)
  end

  it 'fails a LIR on a missing entry that replay would add as a phantom' do
    write_change('1001-0001-LIR-ZZZ.yaml', change('LIR', 'ZZZ', data: { 'code' => 'ZZZ', 'country' => 'iso-3166:zz' }))

    expect(finding_errors).to include(a_string_including('1001-0001-LIR-ZZZ.yaml', 'replay asserted-add', 'LIR "ZZZ"'))
  end

  it 'fails a REP on a missing entry' do
    write_change('1001-0001-REP-ZZZ.yaml', change('REP', 'ZZZ', data: { 'code' => 'ZZZ', 'country' => 'iso-3166:zz' }))

    expect(finding_errors).to include(a_string_including('replay asserted-add', 'REP "ZZZ"'))
  end

  it 'fails a SUP on a missing entry' do
    write_change('1001-0001-SUP-ZZZ.yaml', change('SUP', 'ZZZ'))

    expect(finding_errors).to include(a_string_including('1001-0001-SUP-ZZZ.yaml', 'replay skip', 'SUP conflict'))
  end

  it 'fails an ADD with a blank key' do
    write_change('1001-0001-ADD-blank.yaml', change('ADD', '', data: {}))

    expect(finding_errors).to include(a_string_including('1001-0001-ADD-blank.yaml', 'replay error', 'ADD'))
  end

  it 'fails an ADD whose data lacks the key field' do
    write_change('1001-0001-ADD-CCC.yaml', change('ADD', 'CCC', data: { 'name' => 'no key field here' }))

    expect(finding_errors).to include(a_string_including('1001-0001-ADD-CCC.yaml', 'replay keyless-row'))
  end

  it 'fails a duplicate ADD of an existing key' do
    write_change('1001-0001-ADD-AAA.yaml', change('ADD', 'AAA', data: { 'code' => 'AAA', 'country' => 'iso-3166:aa' }))

    expect(finding_errors).to include(a_string_including('1001-0001-ADD-AAA.yaml', 'replay duplicate-add'))
  end

  it 'fails an unknown action type' do
    write_change('1001-0001-BOGUS-AAA.yaml', change('BOGUS', 'AAA'))

    expect(finding_errors).to include(a_string_including('1001-0001-BOGUS-AAA.yaml', 'replay invalid-change'))
  end

  it 'fails a change file with no type' do
    write_change('1001-0001-none.yaml', 'register' => 'TEST', 'identifier' => { 'code' => 'AAA' })

    expect(finding_errors).to include(a_string_including('1001-0001-none.yaml', 'replay unreadable-change'))
  end

  it 'fails a duplicate YAML mapping key even though a plain load accepts it' do
    File.write(File.join(changes_dir, '1001-0001-ADD-CCC.yaml'), <<~YAML)
      type: ADD
      register: TEST
      ob_issue_no: 1001
      identifier:
        code: CCC
      data:
        code: CCC
        country: iso-3166:cc
        country: iso-3166:dd
    YAML

    expect(finding_errors).to include(a_string_including('1001-0001-ADD-CCC.yaml', 'replay duplicate-yaml-key', '"country"'))
  end

  it 'fails a change dated before the seed issue, which replay silently ignores' do
    write_change('0999-0001-ADD-CCC.yaml',
                 change('ADD', 'CCC', ob: 999, data: { 'code' => 'CCC', 'country' => 'iso-3166:cc' }))

    expect(finding_errors).to include(a_string_including('0999-0001-ADD-CCC.yaml', 'replay pre-seed'))
  end

  it 'fails a seed that is not a list of rows' do
    File.write(File.join(dataset, 'data.yaml'), { 'code' => 'AAA' }.to_yaml)

    expect(finding_errors).to include(a_string_including('data.yaml', 'replay seed-unreadable'))
  end

  describe 'the allowlist' do
    let(:finding) do
      %w[TEST 1001 datasets/1000-Test/changes/1001-0001-SUP-ZZZ.yaml skip].then do |head|
        { register: head[0], ob_issue: 1001, file: head[2], kind: 'skip',
          detail: 'skip SUP {"code" => "ZZZ"} at OB 1001: SUP conflict: key "ZZZ" not present in register TEST' }
      end
    end

    before { write_change('1001-0001-SUP-ZZZ.yaml', change('SUP', 'ZZZ')) }

    it 'accepts exactly the listed finding and counts it' do
      allowed = described_class.new(registers_catalog: catalog, root: root, allowlist: [finding]).verify

      expect(allowed).to be_passed
      expect(allowed.stats).to include(replay_findings: 1, replay_findings_allowed: 1)
    end

    it 'does not let one entry cover a second occurrence in another file' do
      write_change('1001-0002-SUP-ZZZ.yaml', change('SUP', 'ZZZ'))
      allowed = described_class.new(registers_catalog: catalog, root: root, allowlist: [finding]).verify

      expect(allowed.errors).to contain_exactly(a_string_including('1001-0002-SUP-ZZZ.yaml', 'not in the reviewed allowlist'))
    end

    it 'warns, without failing, about an entry that no longer occurs' do
      stale = finding.merge(file: 'datasets/1000-Test/changes/1001-0009-SUP-GONE.yaml')
      allowed = described_class.new(registers_catalog: catalog, root: root, allowlist: [finding, stale]).verify

      expect(allowed).to be_passed
      expect(allowed.warnings).to include(a_string_including('no longer occurs', '1001-0009-SUP-GONE.yaml'))
    end
  end

  describe 'the workflow path filter' do
    let(:workflow) { YAML.load_file(File.expand_path('../../../../.github/workflows/register-state-integrity.yml', __dir__)) }

    it 'generates snapshots before checking them and propagates failures' do
      steps = workflow.fetch('jobs').fetch('integrity').fetch('steps')
      generation = steps.index { |step| step['name'] == 'Generate register snapshots' }
      gate = steps.index { |step| step['name'] == 'Check register state integrity' }

      expect(generation).to be < gate
      expect(steps[generation].fetch('env').fetch('SNAPSHOTS_OUT')).to eq('${{ runner.temp }}/register-snapshots')
      expect(steps[gate].fetch('run')).to eq(
        'bundle exec ruby scripts/check_register_state_integrity.rb --snapshots-root "${{ runner.temp }}/register-snapshots"'
      )
      expect(steps[gate].fetch('env').fetch('BUNDLE_GEMFILE')).to eq('ituob/Gemfile')
      expect(steps[gate]['continue-on-error']).to be_nil
    end

    it 'runs for a datasets.yaml or allowlist change on pull requests and pushes' do
      triggers = workflow.fetch(true) { workflow.fetch('on') }
      [triggers.fetch('pull_request'), triggers.fetch('push')].each do |trigger|
        expect(trigger.fetch('paths')).to include('datasets.yaml', 'scripts/register_state_integrity_allowlist.jsonl')
      end
    end
  end
end
