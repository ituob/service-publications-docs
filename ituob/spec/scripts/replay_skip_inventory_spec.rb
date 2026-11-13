# frozen_string_literal: true

require 'spec_helper'
require 'csv'
require 'tmpdir'
require_relative '../../../scripts/replay_skip_inventory'

RSpec.describe ReplaySkipInventory do
  let(:entry) do
    Ituob::Catalogs::Registers::Entry.new(
      register_id: register, key_field: 'code', seed_issue: seed_issue
    )
  end
  let(:source) do
    Ituob::Registers::InlineChangeSource.new(register_id: register, changes: changes)
  end
  let(:changes) do
    [
      Ituob::Registers::Change.new(
        type: 'SEED', register_id: register, ob_issue_no: seed_issue,
        identifier: { 'code' => '__seed__' }, data: seed_rows
      ),
      Ituob::Registers::Change.new(
        type: action, register_id: register, ob_issue_no: issue,
        identifier: { 'code' => code }, data: patch_data, reference: patch_path
      )
    ]
  end
  let(:seed_rows) { [] }
  let(:patch_data) { nil }
  let(:action) { 'SUP' }
  let(:patch_path) { "fixtures/changes/#{issue}-0001-#{action}.yaml" }
  let(:rows) { described_class.rows_for(entry, source: source) }

  context 'with a seed-issue suppression' do
    let(:register) { 'E118_IIN' }
    let(:seed_issue) { 1161 }
    let(:issue) { 1161 }
    let(:code) { '89 420 06' }

    it 'classifies the existing replay skip as an engine rule and preserves its error' do
      canonical = Ituob::Registers::Replay.new(register_id: register, key_field: 'code', source: source).current
      expect(rows).to eq([
                           [register, issue, patch_path, canonical.errors.fetch(0), 'E',
                            'itu-ob-data/issues/1161/amendments.yaml:573']
                         ])
      expect(rows.first[3]).to include('SUP conflict: key "89 420 06" not present')
    end
  end

  context 'with a mis-filed company-code suppression' do
    let(:register) { 'Q708_ISPC' }
    let(:seed_issue) { 1109 }
    let(:issue) { 1167 }
    let(:code) { 'Genza SA Rue de Lausanne 37 1201 GENEVE' }

    it 'classifies it as mis-filed and supplies the printed block reference' do
      expected = [register, issue, patch_path, 'D',
                  'itu-ob-data/issues/1167/amendments.yaml:3166']
      expect(rows.map { |row| row.values_at(0, 1, 2, 4, 5) }).to eq([expected])
    end
  end

  context 'with a source-gap suppression and a valid row in the same patch' do
    let(:register) { 'X121_DNIC' }
    let(:seed_issue) { 977 }
    let(:issue) { 1081 }
    let(:code) { '206 1' }
    let(:seed_rows) { [{ 'code' => '206 2' }] }
    let(:patch_data) { { 'entries' => [{ 'code' => '206 1' }, { 'code' => '206 2' }] } }

    it 'reports only the missing row and classifies it as a documented gap' do
      expect(rows.length).to eq(1)
      expect(rows.first.values_at(0, 1, 2, 4, 5)).to eq(
        [register, issue, patch_path, 'G', 'itu-ob-data/issues/1081/amendments.yaml:8845']
      )
      expect(rows.first[3]).to include('key "206 1" not present')
      expect(rows.first[3]).not_to include('key "206 2"')
    end

    it 'emits the stable TSV header and round-trips the unmodified error text' do
      table = CSV.parse(described_class.tsv(rows), col_sep: "\t")
      expect(table.first).to eq(%w[register ob_issue patch error class print_ref])
      expect(table.fetch(1)).to eq(rows.first.map(&:to_s))
    end

    it 'generates register and class totals from the same rows' do
      document = described_class.adoc(rows)
      expect(document).to include('Total skips: *1*.', '|X121_DNIC |1',
                                  '|G |Documented source or extraction gap |1')
    end

    it 'retains the dataset patch path through the existing directory loader' do
      Dir.mktmpdir('replay-inventory') do |directory|
        File.write(File.join(directory, 'data.yaml'), YAML.dump(seed_rows))
        Dir.mkdir(File.join(directory, 'changes'))
        path = File.join(directory, 'changes', '1081-0001-SUP.yaml')
        File.write(path, YAML.dump(
                           'type' => action, 'register' => register, 'ob_issue_no' => issue,
                           'identifier' => { 'code' => code }, 'data' => patch_data
                         ))
        directory_source = described_class::Source.new(
          register_id: register, seed_path: directory,
          seed_issue: seed_issue, key_field: entry.key_field
        )
        actual = described_class.rows_for(entry, source: directory_source)
        expect(actual.length).to eq(1)
        expect(actual.first[2]).to eq(path)
      end
    end
  end

  context 'with multiple conflicting rows in one seed-issue patch' do
    let(:register) { 'Q708_ISPC' }
    let(:seed_issue) { 1109 }
    let(:issue) { 1109 }
    let(:code) { '2-125-6' }
    let(:patch_data) { { 'entries' => [{ 'code' => '2-125-6' }, { 'code' => '2-248-4' }] } }

    it 'keeps both per-row reports with the same patch provenance' do
      expect(rows.length).to eq(2)
      expect(rows.map { |row| row[2] }).to eq([patch_path, patch_path])
      expect(rows.map { |row| row[4] }).to eq(%w[E E])
      expect(rows[0][3]).to include('key "2-125-6"')
      expect(rows[1][3]).to include('key "2-248-4"')
      expect(rows.map { |row| row[5] }).to eq([
                                                'itu-ob-data/issues/1109/amendments.yaml:627',
                                                'itu-ob-data/issues/1109/amendments.yaml:669'
                                              ])
    end
  end

  context 'with the textual Note s repetition' do
    let(:register) { 'E164_CC' }
    let(:seed_issue) { 1114 }
    let(:issue) { 1217 }
    let(:code) { '1217-0002' }
    let(:action) { 'LIR' }
    let(:patch_data) { { 'entries' => [] } }

    it 'retains the source-gap classification when the textual patch is replayed' do
      expect(rows.first.values_at(4, 5)).to eq(
        ['G', 'itu-ob-data/issues/1217/amendments.yaml:148-156']
      )
    end
  end

  context 'with a new skip that has no reviewed evidence' do
    let(:register) { 'X121_DNIC' }
    let(:seed_issue) { 977 }
    let(:issue) { 1082 }
    let(:code) { 'unknown' }

    it 'fails instead of inventing a source-gap classification' do
      expect { rows }.to raise_error(/Unclassified skip: X121_DNIC OB 1082/)
    end
  end
end
