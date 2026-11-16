# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'

# Runs the real generator script against a scratch project root: the
# script resolves ob-issues/ and datasets/ relative to its own
# location, so the root holds a copy of the script and a link to the
# gem (whose catalog is the real one).
RSpec.describe 'scripts/migrate_actions_to_changes.rb' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:root) { Dir.mktmpdir('migrate-actions') }

  before do
    FileUtils.mkdir_p(File.join(root, 'scripts'))
    FileUtils.cp(File.join(repo_root, 'scripts/migrate_actions_to_changes.rb'),
                 File.join(root, 'scripts'))
    FileUtils.ln_s(File.join(repo_root, 'ituob'), File.join(root, 'ituob'))
  end

  after { FileUtils.remove_entry(root) }

  def write_patch(issue, slug, name, type:, entries:)
    dir = File.join(root, 'ob-issues', issue.to_s, slug)
    FileUtils.mkdir_p(dir)
    patch = { 'type' => type, 'ob_issue_no' => issue.to_s,
              'identifier' => { 'code' => 'P 1' },
              'data' => { 'position' => 'P 1', 'entries' => entries } }
    File.write(File.join(dir, name), patch.to_yaml)
  end

  def generate(*registers)
    script = File.join(root, 'scripts/migrate_actions_to_changes.rb')
    Open3.capture3('ruby', script, registers.join(','), chdir: root)
  end

  def changes(seed_path)
    Dir.glob(File.join(root, seed_path, 'changes', '*.yaml')).sort.to_h do |path|
      [File.basename(path), YAML.safe_load_file(path, permitted_classes: [Date, Time])]
    end
  end

  describe 'action' do
    it 'takes the action from the type field, not the filename' do
      write_patch(1323, 'e164-cc', '001-ADD.yaml', type: 'SUP',
                                                   entries: [{ 'cc_ic' => '+882 13', 'status' => 'Withdrawn' }])
      _out, _err, status = generate('E164_NOTE_O')

      expect(status).to be_success
      expect(changes('datasets/1114-E.164D-Note-O').values.map { |c| c['type'] }).to eq(['SUP'])
    end

    it 'names the generated file after the type' do
      write_patch(1323, 'e164-cc', '001-ADD.yaml', type: 'SUP',
                                                   entries: [{ 'cc_ic' => '+882 13' }])
      generate('E164_NOTE_O')

      expect(changes('datasets/1114-E.164D-Note-O').keys).to eq(['1323-0001-SUP-_882_13.yaml'])
    end

    it 'warns on stderr when filename and type disagree' do
      write_patch(1323, 'e164-cc', '001-ADD.yaml', type: 'SUP',
                                                   entries: [{ 'cc_ic' => '+882 13' }])
      _out, err, _status = generate('E164_NOTE_O')

      expect(err).to include('ob-issues/1323/e164-cc/001-ADD.yaml', 'type SUP')
    end

    it 'does not warn when the filename carries no register action' do
      write_patch(997, 'm1400-icc', '001-DNK.yaml', type: 'ADD',
                                                    entries: [{ 'country_or_area' => 'Denmark' }])
      _out, err, _status = generate('M1400_ICC')

      expect(err).not_to include('disagree')
    end
  end

  describe 'routing by entry' do
    it 'sends E.164 rows to the Note register that owns their code prefix' do
      write_patch(1114, 'e164-cc', '001-ADD.yaml', type: 'ADD',
                                                   entries: [{ 'cc_ic' => '+883 5140' }])
      write_patch(1120, 'e164-cc', '001-ADD.yaml', type: 'ADD',
                                                   entries: [{ 'cc_ic' => '+882 35' }])
      write_patch(1130, 'e164-cc', '001-ADD.yaml', type: 'ADD',
                                                   entries: [{ 'country_code' => '+44' }])
      generate('E164_CC', 'E164_NOTE_O', 'E164_NOTE_PQ')

      expect(changes('datasets/1114-E.164D-Note-PQ').keys).to eq(['1114-0001-ADD-_883_5140.yaml'])
      expect(changes('datasets/1114-E.164D-Note-O').keys).to eq(['1120-0001-ADD-_882_35.yaml'])
      expect(changes('datasets/1114-E.164D').keys).to eq(['1130-0001-ADD-_44.yaml'])
    end

    it 'records the owning register in the change' do
      write_patch(1120, 'e164-cc', '001-ADD.yaml', type: 'ADD',
                                                   entries: [{ 'cc_ic' => '+882 35' }])
      generate('E164_NOTE_O')

      expect(changes('datasets/1114-E.164D-Note-O').values.first['register']).to eq('E164_NOTE_O')
    end

    it 'splits a mixed E.212 amendment between the main and shared registers' do
      rows = ['901 65', '230 01', '230 02'].map { |code| { 'mcc_mnc_codes' => code } }
      write_patch(1161, 'e212-mnc', '001-ADD.yaml', type: 'ADD', entries: rows)
      generate('E212_MNC', 'E212_SHARED_MCC')

      shared = changes('datasets/1162-E.212-Shared-MCC').values.first
      main = changes('datasets/1162-E.212').values.first
      expect(shared['data']['mcc_mnc_codes']).to eq('901 65')
      expect(main['data']['entries'].map { |e| e['mcc_mnc_codes'] }).to eq(['230 01', '230 02'])
    end
  end

  describe 'empty list repeats' do
    it 'writes no change for a LIR that names no rows' do
      write_patch(1004, 'f32-tdi', '001-LIR.yaml', type: 'LIR', entries: [])
      generate('F32_TDI')

      expect(changes('datasets/980-F.32')).to be_empty
    end

    it 'keeps an empty ADD' do
      write_patch(1004, 'f32-tdi', '001-ADD.yaml', type: 'ADD', entries: [])
      generate('F32_TDI')

      expect(changes('datasets/980-F.32').size).to eq(1)
    end
  end
end
