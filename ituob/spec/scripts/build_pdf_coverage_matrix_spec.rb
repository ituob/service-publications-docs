# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
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

  def doc(dir, lang, dataset, docnumber:, published: '2018-12-01', stem: nil, extra: nil)
    header = [":docnumber: #{docnumber}", (":published-date: #{published}" if published)].compact
    datasets = Array(dataset)
    refs = datasets.each_with_index.map do |d, i|
      suffix = i.zero? ? '' : "_#{i}"
      "data#{suffix}=../../datasets/#{d}/data.yaml,metadata#{suffix}=../../datasets/#{d}/metadata.yaml"
    end
    write("documents/#{dir}/#{[dir, stem, lang].compact.join('-')}.adoc", <<~ADOC)
      = Title
      #{header.join("\n")}
      :doctype: service-publication
      #{extra}
      [yaml2text,#{refs.join(',')}]
      ----
      x
      ----
    ADOC
  end

  def change(dir, name, issue, type: 'ADD')
    write("datasets/#{dir}/changes/#{name}", "type: #{type}\nob_issue_no: '#{issue}'\n")
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
        - register_id: NOSEED
          slug: noseed
          seed_path: datasets/0-NOSEED
        - register_id: SEEDONLY
          slug: seedonly
          seed_issue: 500
          seed_path: datasets/500-SEEDONLY
        - register_id: NI
          slug: ni
          seed_path: datasets/NOISSUE
    YAML
    write('datasets/1161-E.118/data.yaml', "- a: 1\n")
    change('1161-E.118', '1100-0001-ADD-old.yaml', 1100)
    change('1161-E.118', '1200-0001-ADD-new.yaml', 1200)
    change('1161-E.118', '1342-0001-ADD-newest.yaml', 1342)
    write('datasets/669-F.1/data.yaml', "- a: 1\n")
    doc('T-SP-E.118-2018', 'E', '1161-E.118', docnumber: 1161)
    doc('T-SP-E.118-2018', 'F', '1161-E.118', docnumber: 1161)
    doc('T-SP-F.1-1998', 'MSW-E', '669-F.1', docnumber: 'F.1', published: nil)
    doc('T-SP-SR.1-2012', 'MSW-S', '1000-SR.1', docnumber: 1000)
    write('documents/T-SP-E.118-2018/_table.liquid', 'ignored')
    write('documents/notes.txt', 'ignored')
  end

  let(:rows) { described_class.rows(@root) }

  def row_for(standard, lang = nil)
    rows.find { |r| r.standard == standard && (lang.nil? || r.language == lang) }
  end

  def run_script(locale)
    out = File.join(@root, "out-#{locale}.adoc")
    script = File.expand_path('../../../scripts/build_pdf_coverage_matrix.rb', __dir__)
    _, err, status = Open3.capture3(
      { 'LC_ALL' => locale, 'LANG' => locale }, RbConfig.ruby, script, '--root', @root, '--out', out
    )
    [File.binread(out), err, status]
  end

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

  it 'reads non-ASCII documents and regenerates byte-identically under C and UTF-8 locales' do
    write('documents/T-SP-E.118-2018/T-SP-E.118-2018-R.adoc',
          "= Заголовок\n:docnumber: 1161\n\n[yaml2text,data=../../datasets/1161-E.118/data.yaml]\n----\nx\n----\n")
    c, err_c, status_c = run_script('C')
    utf8, err_u, status_u = run_script('en_US.UTF-8')
    expect([status_c.success?, status_u.success?]).to eq([true, true])
    expect(err_c + err_u).not_to match(/invalid byte|Error/)
    expect(c).to eq(utf8)
    expect(c.force_encoding('UTF-8')).to include('| E.118 | 2018 | R | 1161')
  end

  describe 'register currency follows the change loader' do
    let(:newest) { described_class.register_index(@root).fetch('1161-E.118').newest_issue }

    it 'ignores files that are not .yaml/.yml, have no type, or are not hashes' do
      write('datasets/1161-E.118/changes/2000-README.md', 'x')
      write('datasets/1161-E.118/changes/2001-note.yaml', "withdrawn: true\n")
      write('datasets/1161-E.118/changes/2002-list.yaml', "- a\n")
      write('datasets/1161-E.118/changes/3000-0001-ADD-x.yaml.bak', "type: ADD\nob_issue_no: 3000\n")
      expect(newest).to eq(1342)
    end

    it 'takes the issue from the file content, not the filename prefix' do
      change('1161-E.118', '4000-0001-ADD-x.yaml', 1400)
      expect(newest).to eq(1400)
    end

    it 'reads .yml files and ignores changes before the seed' do
      change('1161-E.118', '5000-0001-ADD-x.yml', 1500)
      change('1161-E.118', '0900-0001-ADD-x.yaml', 5)
      expect(newest).to eq(1500)
    end

    it 'treats a register with no seed issue as seeded at 0 and a seed-only register as its seed' do
      change('0-NOSEED', '0050-0001-ADD-x.yaml', 50)
      index = described_class.register_index(@root)
      expect([index.fetch('0-NOSEED').newest_issue, index.fetch('500-SEEDONLY').newest_issue]).to eq([50, 500])
    end

    it 'does not compare a change at exactly the seed issue as newer' do
      change('500-SEEDONLY', '0500-0001-ADD-x.yaml', 500)
      write('datasets/500-SEEDONLY/data.yaml', "- a: 1\n")
      doc('T-SP-S.5-2018', 'E', '500-SEEDONLY', docnumber: 500)
      expect(row_for('S.5').flag).to eq('current')
    end
  end

  describe 'dataset references' do
    it 'come from the yaml2text block, not from comments or prose' do
      doc('T-SP-E.118-2019', 'E', '1161-E.118', docnumber: 1161,
                                               extra: "// old path was datasets/0001-OLD/data.yaml\nSee datasets/0002-PROSE/data.yaml.\n")
      row = row_for('E.118', 'E')
      expect(described_class.rows(@root).find { |r| r.year == '2019' }.unmapped).to eq([])
      expect(row.unmapped).to eq([])
      expect(described_class.rows(@root).find { |r| r.year == '2019' }.issue).to eq(1161)
    end

    it 'takes the maximum issue as as-of and compares each register with its own dataset' do
      change('669-F.1', '1000-0001-ADD-x.yaml', 1000)
      doc('T-SP-M.1-2018', 'E', %w[1161-E.118 669-F.1], docnumber: 1)
      row = row_for('M.1')
      expect([row.issue, row.datasets]).to eq([1161, [['1161-E.118', 1161], ['669-F.1', 669]]])
      expect(row.flag).to eq('outdated: e118-iin at 1342, f1 at 1000')
      expect(row.newest).to eq(1342)
      expect(described_class.row_cells(row)).to include('1161 (max of 1161-E.118=1161, 669-F.1=669)')
    end

    it 'sorts a document\'s datasets and lists unmapped ones with a suffix' do
      doc('T-SP-M.2-2018', 'E', %w[1161-E.118 1000-AA 0999-ZZ], docnumber: 1)
      row = row_for('M.2')
      expect(row.registers.map(&:slug)).to eq(['e118-iin'])
      expect([row.issue, row.unmapped]).to eq([1161, %w[0999-ZZ 1000-AA]])
      expect(described_class.row_cells(row)).to include('e118-iin, 0999-ZZ (no register), 1000-AA (no register)')
    end

    it 'reports unknown when no dataset has an issue number' do
      doc('T-SP-M.3-2018', 'E', 'NOISSUE', docnumber: 1)
      row = row_for('M.3')
      expect([row.issue, row.flag]).to eq([nil, 'unknown (no numbered dataset)'])
      expect(described_class.row_cells(row)).to start_with('| M.3 | 2018 | E |  | 1 |')
    end
  end

  describe 'duplicate rows' do
    it 'fail loudly when two files share standard, year and language' do
      doc('T-SP-E.118-2018', 'E', '1161-E.118', docnumber: 1161, stem: 'MSW')
      expect { rows }.to raise_error(ArgumentError, /E\.118 2018 E: .*-E\.adoc, .*-MSW-E\.adoc/)
    end

    it 'accept a stem on a file that is the only one for its language' do
      expect(row_for('F.1', 'E').file).to eq('T-SP-F.1-1998-MSW-E.adoc')
    end
  end

  it 'escapes a pipe in a cell so the table keeps its columns' do
    doc('T-SP-E.118-2018', 'S', '1161-E.118', docnumber: 'A|B')
    cells = described_class.row_cells(row_for('E.118', 'S'))
    expect(cells).to include('A\\|B')
    expect(cells.gsub('\\|', '').count('|')).to eq(8)
  end

  it 'covers every language letter' do
    expect(described_class::LANGUAGES).to eq(%w[A C E F R S])
    %w[A C R].each { |l| doc('T-SP-L.1-2018', l, '1161-E.118', docnumber: 1) }
    expect(rows.select { |r| r.standard == 'L.1' }.map(&:language)).to eq(%w[A C R])
  end

  it 'lists documents of a publication in file order' do
    doc('T-SP-L.2-2018', 'S', '1161-E.118', docnumber: 1)
    doc('T-SP-L.2-2018', 'E', '1161-E.118', docnumber: 1)
    doc('T-SP-L.2-2018', 'F', '1161-E.118', docnumber: 1)
    expect(rows.select { |r| r.standard == 'L.2' }.map(&:language)).to eq(%w[E F S])
  end

  describe '.render' do
    it 'is deterministic and carries one table row per document row' do
      first = described_class.render(rows)
      expect(described_class.render(described_class.rows(@root))).to eq(first)
      expect(first.lines.grep(/\A\| (E\.118|F\.1|SR\.1) \|/).size).to eq(4)
      expect(first).to include('* Publications: 3', '* Publication x language rows: 4')
      expect(first).to include('| E.118 | 2018 | E | 1161 | 1161 | 2018-12-01 | e118-iin | outdated: e118-iin at 1342')
    end
  end
end
