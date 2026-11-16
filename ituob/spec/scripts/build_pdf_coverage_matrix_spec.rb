# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../scripts/build_pdf_coverage_matrix'

RSpec.describe PdfCoverageMatrix do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def doc(dir, lang, dataset, docnumber:, published: '2018-12-01')
    header = [":docnumber: #{docnumber}", (":published-date: #{published}" if published)].compact
    write("documents/#{dir}/#{dir}-#{lang}.adoc", <<~ADOC)
      = Title
      #{header.join("\n")}
      :doctype: service-publication

      [yaml2text,data=../../datasets/#{dataset}/data.yaml,metadata=../../datasets/#{dataset}/metadata.yaml]
      ----
      x
      ----
    ADOC
  end

  before do
    write('catalogs/registers.yaml', <<~YAML)
      registers:
        - register_id: E118_IIN
          slug: e118-iin
          seed_issue: 1161
          seed_path: datasets/1161-E.118
        - register_id: F1
          slug: f1
          seed_issue: 669
          seed_path: datasets/669-F.1
    YAML
    write('datasets/1161-E.118/data.yaml', "- a: 1\n")
    write('datasets/1161-E.118/changes/1100-0001-ADD-old.yaml', "type: ADD\n")
    write('datasets/1161-E.118/changes/1200-0001-ADD-new.yaml', "type: ADD\n")
    write('datasets/1161-E.118/changes/1342-0001-ADD-newest.yaml', "type: ADD\n")
    write('datasets/669-F.1/data.yaml', "- a: 1\n")
    doc('T-SP-E.118-2018', 'E', '1161-E.118', docnumber: 1161)
    doc('T-SP-E.118-2018', 'F', '1161-E.118', docnumber: 1161)
    doc('T-SP-F.1-1998', 'MSW-E', '669-F.1', docnumber: 'F.1', published: nil)
    doc('T-SP-SR.1-2012', 'MSW-S', '1000-SR.1', docnumber: 1000)
    write('documents/T-SP-E.118-2018/_table.liquid', 'ignored')
    write('documents/notes.txt', 'ignored')
  end

  let(:rows) { described_class.rows(@root) }

  it 'emits one row per publication and language, sorted, ignoring non-documents' do
    expect(rows.map { |r| [r.standard, r.year, r.language] }).to eq(
      [%w[E.118 2018 E], %w[E.118 2018 F], %w[F.1 1998 E], %w[SR.1 2012 S]]
    )
  end

  it 'flags an edition older than the register state, ignoring changes before the seed' do
    row = rows.first
    expect(row.registers.map(&:slug)).to eq(['e118-iin'])
    expect(row.newest).to eq(1342)
    expect(row.flag).to eq('outdated: e118-iin at 1342')
  end

  it 'takes the as-of issue from the dataset, not from a non-numeric header docnumber' do
    row = rows.find { |r| r.standard == 'F.1' }
    expect([row.issue, row.docnumber, row.flag]).to eq([669, 'F.1', 'current'])
  end

  it 'reports a dataset absent from the register catalog as having no register' do
    row = rows.find { |r| r.standard == 'SR.1' }
    expect([row.registers, row.unmapped, row.flag]).to eq([[], ['1000-SR.1'], 'no register'])
  end

  describe '.render' do
    it 'is deterministic and carries one table row per document row' do
      first = described_class.render(rows)
      expect(described_class.render(described_class.rows(@root))).to eq(first)
      expect(first.lines.grep(/\A\| (E\.118|F\.1|SR\.1) \|/).size).to eq(4)
      expect(first).to include('| E.118 | 2018 | E | 1161 | 1161 | 2018-12-01 | e118-iin | outdated: e118-iin at 1342')
    end
  end
end
