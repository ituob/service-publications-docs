# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Two print-side normalisations of scripts/ob_print_to_patch_coverage.rb, each
# with a negative control that must stay unmapped:
#   - a page letter printed without its number ("P  Georgia  ADD")
#   - a superscript zero glued to the text it follows ("n" + sup "0" = "n0")
RSpec.describe 'scripts/ob_print_to_patch_coverage.rb print normalisation' do
  let(:script) { File.expand_path('../../../scripts/ob_print_to_patch_coverage.rb', __dir__) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def text_node(text, superscript: false)
    marks = superscript ? "                            marks:\n                              - type: superscript\n" : ''
    "                          - type: text\n                            text: #{text.inspect}\n#{marks}"
  end

  def para(text)
    "          - type: paragraph\n            content:\n              - type: text\n                text: #{text.inspect}\n"
  end

  def row(*cells)
    cs = cells.map do |nodes|
      "                  - type: table_cell\n                    content:\n                      - type: paragraph\n" \
        "                        content:\n#{Array(nodes).join}"
    end
    "          - type: table\n            content:\n              - type: table_row\n                content:\n#{cs.join}"
  end

  # Returns the printed texts the script leaves unmapped.
  def unmapped_for(blocks, networks, position: '15')
    Dir.mktmpdir('coverage-marks') do |dir|
      msg = "  - type: amendment\n    target:\n      publication: E212_MNC\n    contents:\n      en:\n        type: doc\n" \
            "        content:\n#{blocks.join}"
      write(File.join(dir, 'data/issues/700/amendments.yaml'), "messages:\n#{msg}")
      write(File.join(dir, 'ob/700/e212-mnc/001-ADD.yaml'), <<~YAML)
        type: ADD
        data:
          position: #{position.inspect}
          entries:
          - mcc_mnc_codes: 282 06
            country_or_area:
              en: Georgia
            networks: #{networks}
      YAML
      write(File.join(dir, 'datasets/1162-E.212/changes/0700-0001-ADD-282_06.yaml'), "type: ADD\ndata:\n  mcc: '282 06'\n")
      write(File.join(dir, 'catalog.yaml'), "registers:\n- register_id: E212_MNC\n  slug: e212-mnc\n  seed_path: datasets/1162-E.212\n")
      env = { 'ITU_OB_DATA_ROOT' => File.join(dir, 'data/issues'), 'OB_ISSUES_ROOT' => File.join(dir, 'ob'),
              'DATASETS_ROOT' => File.join(dir, 'datasets'), 'REGISTERS_CATALOG' => File.join(dir, 'catalog.yaml'),
              'COVERAGE_OUT_DIR' => File.join(dir, 'out'), 'COVERAGE_MIN_ISSUE' => '669' }
      _out, err, st = Open3.capture3(env, RbConfig.ruby, script)
      raise err unless st.success?

      rows = File.readlines(File.join(dir, 'out/100-05-unmapped-lines.tsv'), chomp: true).map { |l| l.split("\t", -1) }
      head = rows.shift
      rows.map { |r| head.zip(r).to_h['text'] }
    end
  end

  def plain(text) = text_node(text)

  it 'maps a lone page letter before the country heading' do
    expect(unmapped_for([para('P Georgia ADD'), row(plain('Georgia'), plain('282 06'), plain('Compatel'))], 'Compatel')).to eq([])
  end

  it 'keeps an unknown leading letter unmapped (negative control)' do
    expect(unmapped_for([para('Q Georgia ADD'), row(plain('Georgia'), plain('282 06'), plain('Compatel'))], 'Compatel'))
      .to eq(['Q Georgia ADD'])
  end

  it 'attaches a superscript zero to the text it follows' do
    cell = [plain('n'), text_node('0', superscript: true), plain(' 28,6'), text_node('0', superscript: true)]
    expect(unmapped_for([row(plain('Georgia'), plain('282 06'), cell)], 'n0 28,60')).to eq([])
  end

  it 'does not attach an ordinary zero (negative control)' do
    cell = [plain('n'), plain('0'), plain(' 28,6'), plain('0')]
    expect(unmapped_for([row(plain('Georgia'), plain('282 06'), cell)], 'n0 28,60')).not_to eq([])
  end

  it 'keeps the space before a footnote-marker superscript that is not zero (negative control)' do
    cell = [plain('Compatel'), text_node('1', superscript: true)]
    expect(unmapped_for([row(plain('Georgia'), plain('282 06'), cell)], 'Compatel1')).not_to eq([])
  end
end
