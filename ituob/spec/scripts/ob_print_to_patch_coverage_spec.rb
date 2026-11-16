# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

# Runs the real scripts/ob_print_to_patch_coverage.rb as a subprocess over a
# tiny synthetic tree and asserts how every printed line is classified.
RSpec.describe 'scripts/ob_print_to_patch_coverage.rb' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:script) { File.join(repo_root, 'scripts/ob_print_to_patch_coverage.rb') }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def para(*texts)
    lines = texts.map { |t| "          - type: paragraph\n            content:\n              - type: text\n                text: #{t.inspect}\n" }
    lines.join
  end

  def table_row(*cells)
    cs = cells.map do |c|
      "                  - type: table_cell\n                    content:\n                      - type: paragraph\n" \
        "                        content:\n                          - type: text\n                            text: #{c.inspect}\n"
    end
    "          - type: table\n            content:\n              - type: table_row\n                content:\n#{cs.join}"
  end

  def message(pub, *blocks)
    "  - type: amendment\n    target:\n      publication: #{pub}\n    contents:\n      en:\n        type: doc\n" \
      "        content:\n#{blocks.join}"
  end

  def run_script(env)
    Open3.capture3(env, RbConfig.ruby, script)
  end

  def tsv(path)
    rows = File.readlines(path, chomp: true).map { |l| l.split("\t", -1) }
    head = rows.shift
    rows.map { |r| head.zip(r).to_h }
  end

  around do |ex|
    Dir.mktmpdir('coverage-spec') do |dir|
      @dir = dir
      @out = File.join(dir, 'out')
      msgs = [
        message('E212_MNC',
                para('P 15 Georgia ADD'),
                table_row('Country/Geographical area', 'MCC + MNC*', 'Operator/Network'),
                table_row('Georgia', '282 06', 'JSC Compatel'),
                para('A line nobody stored anywhere')),
        message('T35_NA', para('Department:'))
      ].join
      write(File.join(dir, 'data/issues/700/amendments.yaml'), "messages:\n#{msgs}")
      write(File.join(dir, 'ob/700/e212-mnc/001-ADD.yaml'), <<~YAML)
        type: ADD
        data:
          position: P 15
          entries:
          - mcc_mnc_codes: 282 06
            country_or_area:
              en: Georgia
            networks: JSC Compatel
      YAML
      write(File.join(dir, 'datasets/1162-E.212/changes/0700-0001-ADD-282_06.yaml'), "type: ADD\ndata:\n  mcc: '282 06'\n")
      write(File.join(dir, 'catalog.yaml'), <<~YAML)
        registers:
        - register_id: E212_MNC
          slug: e212-mnc
          seed_path: datasets/1162-E.212
      YAML
      @env = { 'ITU_OB_DATA_ROOT' => File.join(dir, 'data/issues'), 'OB_ISSUES_ROOT' => File.join(dir, 'ob'),
               'DATASETS_ROOT' => File.join(dir, 'datasets'), 'REGISTERS_CATALOG' => File.join(dir, 'catalog.yaml'),
               'COVERAGE_OUT_DIR' => @out, 'COVERAGE_MIN_ISSUE' => '669' }
      ex.run
    end
  end

  it 'classifies mapped, excluded and unmapped lines and cites the source line of the unmapped one' do
    out, err, st = run_script(@env)
    expect(st.success?).to be(true), err
    expect(out).to include('printed=5 ')

    unmapped = tsv(File.join(@out, '100-05-unmapped-lines.tsv'))
    expect(unmapped.map { |r| r['text'] }).to eq(['A line nobody stored anywhere'])
    expect(unmapped.first).to include('issue' => '700', 'register' => 'e212-mnc',
                                      'cause' => 'no_token_in_register_patches')
    expect(unmapped.first['source']).to match(%r{\Aissues/700/amendments\.yaml:\d+\z})

    excluded = tsv(File.join(@out, '100-05-excluded-lines.tsv'))
    expect(excluded.map { |r| [r['rule'], r['text']] }).to contain_exactly(
      ['column_header', 'Country/Geographical area | MCC + MNC* | Operator/Network'],
      ['form_label_only', 'Department:']
    )
  end

  it 'reports totals per register and per issue and is deterministic' do
    run_script(@env)
    first = File.read(File.join(@out, '100-05-print-to-patch-coverage.md'))
    run_script(@env)
    expect(File.read(File.join(@out, '100-05-print-to-patch-coverage.md'))).to eq(first)
    expect(first).to include('## Per register', '## Per issue', '| e212-mnc | 4 | 2 |', '| 700 | 5 |')
  end

  it 'never lets an exclusion rule hide a line that maps to a patch' do
    write(File.join(@dir, 'ob/700/t35-na/001-LIR.yaml'), "type: LIR\ndata:\n  department: Department Works\n")
    _o, err, st = run_script(@env)
    expect(st.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-excluded-lines.tsv')).map { |r| r['text'] }).not_to include('Department:')
    expect(File.read(File.join(@out, '100-05-print-to-patch-coverage.md'))).to include('| t35-na | 1 | 1 | 1 |')
  end

  it 'keeps the slug table identical to scripts/build_ob_issues.rb' do
    src = File.read(File.join(repo_root, 'scripts/build_ob_issues.rb'))
    block = src[/DATASET_SLUG_BY_PUBLICATION = \{(.*?)^\}/m, 1]
    build_map = block.scan(/'([^']+)' => '([^']+)'/).to_h
    require script
    expect(PrintToPatchCoverage::SLUG_BY_PUBLICATION).to eq(build_map)
  end
end
