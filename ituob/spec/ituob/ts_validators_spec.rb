# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

# The Worker validates a member's submitted register change against the
# TypeScript validators generated from messages.lml (the same ontology
# the gem compiles). This spec proves the generated module (a) is
# deterministic, (b) accepts every stored instance of the submittable
# classes (the register action envelope and each register's amendment
# payload), and (c) rejects crafted bad inputs with field pointers.
RSpec.describe 'generated TypeScript validators' do
  root = File.expand_path('../../..', __dir__)
  let(:generator) { File.join(root, 'scripts', 'generate_ts_types.rb') }
  let(:runner) { File.join(root, 'ituob', 'spec', 'support', 'ts_validator_check.mjs') }

  node_version = begin
    out, status = Open3.capture2e('node', '--version')
    status.success? ? out.strip.delete_prefix('v').split('.').map(&:to_i) : nil
  rescue Errno::ENOENT
    nil
  end
  node_ok = node_version && ((node_version <=> [22, 6, 0]) >= 0)

  before(:all) do
    # CI must never silently skip the corpus proof.
    raise 'node >= 22.6 is required to run the generated validators' if !node_ok && ENV['CI']
  end

  let(:out_dir) { @out_dir ||= Dir.mktmpdir('ts-validators') }
  after { FileUtils.rm_rf(@out_dir) if @out_dir }

  def generate(dir, name)
    env = {
      'SITE_TYPES_PATH' => File.join(dir, "#{name}.types.ts"),
      'SITE_VALIDATORS_PATH' => File.join(dir, "#{name}.validators.ts"),
    }
    out, status = Open3.capture2e(env, RbConfig.ruby, generator)
    raise "generator failed: #{out}" unless status.success?

    [env['SITE_TYPES_PATH'], env['SITE_VALIDATORS_PATH']]
  end

  def run_cases(validators_path, cases, dir)
    path = File.join(dir, 'cases.json')
    File.write(path, JSON.generate(cases))
    out, err, status = Open3.capture3('node', '--experimental-strip-types', '--no-warnings', runner, validators_path, path)
    raise "validator runner failed: #{err}" unless status.success?

    JSON.parse(out).to_h { |r| [r['id'], r['issues']] }
  end

  it 'emits a deterministic validators module beside the types file' do
    _t1, v1 = generate(out_dir, 'a')
    _t2, v2 = generate(out_dir, 'b')
    expect(File.read(v1)).to eq(File.read(v2))
    expect(File.read(v1)).to include('export function validateClass', '"RegisterChange"', '"ActionType"')
  end

  describe 'against the corpus and crafted inputs', if: node_ok do
    # Submittable classes: the register action envelope (RegisterChange)
    # and the amendment class named by each file's data._class.
    def submittable_cases
      issues = Dir.children(OB_ISSUES_ROOT).grep(/\A\d+\z/).sort
      issues.flat_map do |issue|
        Dir.glob(File.join(OB_ISSUES_ROOT, issue, '**', '*.yaml')).sort.flat_map do |path|
          rel = path.delete_prefix("#{File.join(OB_ISSUES_ROOT, issue)}/")
          next [] unless Ituob::Support::CorpusTree.class_name_for(rel) == 'RegisterChange'

          data = YAML.load_file(path, permitted_classes: [Date, Time], aliases: true)
          [
            { 'id' => "#{issue}/#{rel}#envelope", 'class' => 'RegisterChange', 'value' => data },
            { 'id' => "#{issue}/#{rel}#data", 'class' => data.dig('data', '_class'), 'value' => data['data'] },
          ]
        end
      end
    end

    it 'accepts every stored instance of the submittable classes' do
      _types, validators = generate(out_dir, 'corpus')
      cases = submittable_cases
      # Guard against a vacuous pass: every keyed register class is exercised.
      classes = cases.map { |c| c['class'] }.uniq
      expect(cases.length).to be > 1_000
      expect(classes).to include('E118Amendment', 'E164ACNAmendment', 'E212MNCAmendment', 'RegisterChange')

      results = run_cases(validators, cases, out_dir)
      rejected = results.reject { |_id, issues| issues.empty? }
      expect(results.length).to eq(cases.length)
      expect(rejected.first(5)).to eq([])
    end

    it 'rejects crafted bad inputs with a field pointer and code' do
      _types, validators = generate(out_dir, 'bad')
      entry = { 'country_or_area' => { 'en' => 'Chad' }, 'company_name' => 'Acme', 'tel' => ['+235 1'], 'issue_id_number' => '89 1' }
      good = { '_class' => 'E118Amendment', 'entries' => [entry], 'notes' => [] }
      envelope = { 'type' => 'ADD', 'ob_issue_no' => '1300', 'identifier' => { 'code' => '1300-001' }, 'data' => good }
      bad = {
        'missing-identifier' => ['RegisterChange', envelope.reject { |k, _| k == 'identifier' }, 'required', 'identifier'],
        'enum' => ['RegisterChange', envelope.merge('type' => 'YOLO'), 'enum', 'type'],
        'integer' => ['RegisterChange', envelope.merge('ob_issue_no' => 'abc'), 'type', 'ob_issue_no'],
        'hash' => ['RegisterChange', envelope.merge('data' => 'text'), 'type', 'data'],
        'envelope-unknown-key' => ['RegisterChange', envelope.merge('bogus' => 1), 'unknown', 'bogus'],
        'nested-class' => ['RegisterChange', envelope.merge('identifier' => 'x'), 'type', 'identifier'],
        'unknown-attr' => ['E118Amendment', good.merge('company' => 'x'), 'unknown', 'company'],
        'scalar-type' => ['E118Amendment', good.merge('entries' => [entry.merge('company_name' => 7)]), 'type', 'entries[0].company_name'],
        'collection-not-list' => ['E118Amendment', good.merge('entries' => [entry.merge('tel' => '+235 1')]), 'type', 'entries[0].tel'],
        'collection-item' => ['E118Amendment', good.merge('notes' => ['ok', 3]), 'type', 'notes[1]'],
        'entries-not-list' => ['E118Amendment', good.merge('entries' => entry), 'type', 'entries'],
        'entry-not-object' => ['E118Amendment', good.merge('entries' => ['x']), 'type', 'entries[0]'],
        'multilingual-type' => ['E118Amendment', good.merge('entries' => [entry.merge('country_or_area' => 'Chad')]), 'type', 'entries[0].country_or_area'],
        'multilingual-key' => ['E118Amendment', good.merge('entries' => [entry.merge('country_or_area' => { 'en' => 1 })]), 'type', 'entries[0].country_or_area.en'],
        'date' => ['E118Amendment', good.merge('position_on' => 'next tuesday'), 'type', 'position_on'],
        'unknown-class' => ['NoSuchClass', {}, 'unknown', ''],
        'payload-not-object' => ['E118Amendment', [], 'type', ''],
      }
      cases = bad.map { |id, (klass, value, _c, _p)| { 'id' => id, 'class' => klass, 'value' => value } }
      cases << { 'id' => 'control-good', 'class' => 'E118Amendment', 'value' => good }
      cases << { 'id' => 'control-envelope', 'class' => 'RegisterChange', 'value' => envelope }
      results = run_cases(validators, cases, out_dir)

      bad.each do |id, (_klass, _value, code, path)|
        found = results.fetch(id).map { |i| [i['code'], i['path']] }
        expect(found).to include([code, path]), "#{id}: expected #{[code, path].inspect}, got #{found.inspect}"
      end
      expect(results.fetch('control-good')).to eq([])
      expect(results.fetch('control-envelope')).to eq([])
    end

    it 'treats HashOrText as object-or-string, DateOrText as string, Hash as object' do
      _types, validators = generate(out_dir, 'kinds')
      cases = [
        { 'id' => 'hot-obj', 'class' => 'GeneralMiscCommunications', 'value' => { 'contents' => { 'a' => 1 } } },
        { 'id' => 'hot-str', 'class' => 'GeneralMiscCommunications', 'value' => { 'contents' => 'free text' } },
        { 'id' => 'hot-num', 'class' => 'GeneralMiscCommunications', 'value' => { 'contents' => 5 } },
        { 'id' => 'hash-str', 'class' => 'IssueMetadata', 'value' => { 'languages' => 'en' } },
        { 'id' => 'dot-str', 'class' => 'IssueMetadata', 'value' => { 'publication_date' => 'see note' } },
        { 'id' => 'dot-num', 'class' => 'IssueMetadata', 'value' => { 'publication_date' => 20_240_101 } },
      ]
      results = run_cases(validators, cases, out_dir)
      expect(results['hot-obj']).to eq([])
      expect(results['hot-str']).to eq([])
      expect(results['hot-num'].map { |i| i['code'] }).to eq(['type'])
      expect(results['hash-str'].map { |i| i['code'] }).to eq(['type'])
      expect(results['dot-str']).to eq([])
      expect(results['dot-num'].map { |i| i['code'] }).to eq(['type'])
    end
  end
end
