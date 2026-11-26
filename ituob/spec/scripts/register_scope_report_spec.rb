# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require_relative '../../../scripts/register_scope_report'

RSpec.describe RegisterScopeReport do
  let(:root) { Dir.mktmpdir }
  let(:catalog) { File.join(root, 'catalogs', 'registers.yaml') }
  let(:rows) { described_class.rows(root).to_h { |r| [r.register_id, r] } }
  let(:inventory) do
    { 'inventory' => [{ 'number' => 3, 'class' => 'unresolved' }, { 'number' => 7, 'class' => 'a' }] }
  end

  def touch(*parts)
    path = File.join(root, *parts)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "type: ADD\n")
  end

  before do
    FileUtils.mkdir_p(File.dirname(catalog))
    File.write(catalog, <<~YAML)
      registers:
        - register_id: AAA
          slug: aaa
          seed_issue: 1000
          seed_path: datasets/1000-AAA
          seed_includes_seed_issue: true
        - register_id: BBB
          slug: bbb
          source_slug: bbb-src
        - register_id: CCC
          slug: ccc
          seed_issue: 5
          seed_path: datasets/5-CCC
    YAML
    [1005, 1002, 1010].each { |n| touch('ob-issues', n.to_s, 'aaa', '001-ADD.yaml') }
    touch('ob-issues', '1003', 'aaa', 'notes.bak')
    touch('ob-issues', '1004', 'bbb-src', '001-ADD.yaml')
    touch('ob-issues', 'draft', 'aaa', '001-ADD.yaml')
    FileUtils.mkdir_p(File.join(root, 'docs', 'backfill'))
    File.write(File.join(root, 'docs', 'backfill', 'inventory.yaml'), inventory.to_yaml)
  end

  after do
    FileUtils.rm_rf(root)
    Ituob::Catalogs::Registers.load!
  end

  it 'reports the seed and the earliest and latest action issue per register' do
    expect(rows['AAA']).to have_attributes(seed_issue: 1000, seed_path: 'datasets/1000-AAA',
                                           seed_includes_seed_issue: true,
                                           earliest_action: 1002, latest_action: 1010)
  end

  it 'reads actions from source_slug and leaves a register without actions or seed empty' do
    expect(rows['BBB']).to have_attributes(seed_issue: nil, earliest_action: 1004, latest_action: 1004)
    expect(rows['CCC']).to have_attributes(earliest_action: nil, latest_action: nil)
  end

  it 'flags absent numbers before the seed' do
    expect(rows.transform_values(&:absent_before_seed)).to eq('AAA' => true, 'BBB' => nil, 'CCC' => false)
  end

  it 'computes the gap to № 1 from the seed, else the earliest action' do
    expect(rows.transform_values(&:gap_to_first)).to eq('AAA' => 999, 'BBB' => 1003, 'CCC' => 4)
  end

  it 'lists every catalog register in the adoc' do
    adoc = described_class.adoc(described_class.rows(root))
    expect(adoc).to include('| AAA | aaa | 1000', '| BBB | bbb-src', '| CCC | ccc | 5', '== Decisions still open')
  end
end
