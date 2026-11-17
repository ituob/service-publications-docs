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
        - slug: t35-na
        - slug: e164-cc
        - slug: e118-iin
        - slug: list-viii
        - slug: m1400-icc
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

  it 'maps only register action files and register text, preserving other-register actions' do
    lines = ['211 South Sudan Republic of', '31 August 2011', 'Example bulletin assignment',
             'Unstructured register metadata', 'Other Register Telecom', 'Register narrative coverage']
    write(File.join(@dir, 'data/issues/700/amendments.yaml'),
          "messages:\n#{message('E164_CC', para(*lines))}")
    write(File.join(@dir, 'ob/700/iptn/001.yaml'), "type: iptn\ndata: 211 South Sudan Republic of\n")
    write(File.join(@dir, 'ob/700/general/approved_recommendations.yaml'), "date: 31 August 2011\n")
    write(File.join(@dir, 'ob/700/general/text.yaml'), "text: Example bulletin assignment\n")
    write(File.join(@dir, 'ob/700/e164-cc/metadata.yaml'), "text: Unstructured register metadata\n")
    write(File.join(@dir, 'ob/700/general/001-ADD.yaml'), "type: ADD\ndata: Example bulletin assignment\n")
    write(File.join(@dir, 'ob/700/e212-mnc/002-ADD.yaml'), "type: ADD\ndata: Other Register Telecom\n")
    write(File.join(@dir, 'ob/700/e164-cc/text.yaml'), "text: Register narrative coverage\n")

    out, err, st = run_script(@env)

    expect(st.success?).to be(true), err
    expect(out).to include('mapped=2 ', 'other=1 ')
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |r| r['text'] }).to eq(lines.first(4))
  end

  it 'preserves typed text amendments for registers outside the catalog' do
    write(File.join(@dir, 'data/issues/701/amendments.yaml'),
          "messages:\n#{message('Coast Station Identification Numbers', para('Bahamas 3070 3079'))}")
    write(File.join(@dir, 'ob/701/coast-station-identification-numbers/text.yaml'),
          "_class: TextAmendment\ncontents: Bahamas 3070 3079\n")

    _out, err, status = run_script(@env)

    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |r| r['text'] }).not_to include('Bahamas 3070 3079')
    expect(File.read(File.join(@out, '100-05-print-to-patch-coverage.md'))).to include('| coast-station-identification-numbers | 1 | 1 | 0 | 0 | 1 |')
  end

  describe 'printed-line matching' do
    before { require script }

    let(:tok) { PrintToPatchCoverage::Tok }
    let(:rule_ids) do
      lambda do |text|
        cells = (text.include?(' | ') ? text.split(' | ') : text.split(/[[:space:]]{2,}/)).map { |c| tok.words(c).join(' ') }
        PrintToPatchCoverage::EXCLUSION_RULES.select { |r| r.match.call(text, tok.of_print(text), cells) }.map(&:id)
      end
    end

    [
      ['shared-code assignment', 'e164-cc', 'Associated with shared code 883, network Example Telecom assigned 999'],
      ['telephone suffix', 'e118-iin', 'Alice Tel: +358 40 866 85829'],
      ['telephone prefix', 'e118-iin', 'Alice Tel: +999 358 40 866 8582'],
      ['inline coordinates', 'list-viii', '2. Geographical coordinates: 46 N 6 E'],
      ['extra-territorial assignment', 'e212-mnc', 'Sweden | 240 99 | Example operator assigned extra-territorial use'],
      ['parenthesized carrier code', 'm1400-icc', 'P 17 Sweden ADD Example Telecom (carrier code EXAMPLE)'],
      ['single-digit country code', 'e164-cc', 'Country code | 7'],
      ['embedded ISPC assignment', 'q708-ispc', '(According to Recommendation ITU-T Q.708, assign ISPC 2-001-0 to Example Telecom)']
    ].each do |name, slug, text|
      it "counts the breaker's #{name} as unmapped real content" do
        patch = PrintToPatchCoverage::Patch.new(
          path: 'synthetic.yaml', layer: :ob_issues, kind: :structured,
          tokens: Set.new(tok.of_patch_value('Alice +358 40 8668582')),
          numbers: Set['358408668582']
        )
        index = double('patch index', for_issue: { 'e118-iin' => [patch] })
        line = PrintToPatchCoverage::Line.new(
          issue: 700, slug: slug, text: text,
          tokens: Set.new(tok.with_unpadded(tok.of_print(text)))
        )

        result = PrintToPatchCoverage::Classifier.new(index).classify(line, collision: false)

        expect(result.status).to eq(:unmapped)
        expect(result.missing).not_to be_empty
      end
    end

    it 'meets a detached ordinal or unit digit on either spelling, but never the page marker' do
      expect(tok.of('12920 SE 38th Street')).to include('38th')
      expect(tok.of_print('SE 38 th Street')).to include('38th')
      expect(tok.of_print('SE 38 th Street')).not_to include('38', 'th')
      expect(tok.of('-140 dBW/m 2')).to include('m2')
      expect(tok.of_print('-140 dBW/m2')).to include('m2')
      expect(tok.of_print('P  24  Gibraltar')).to include('p', '24')
    end

    it 'excludes page-marker headings that carry only page and action directives' do
      ['P 9 LIR', 'P 29 to 30 REP all information by:', 'P 26 SUP (delete)',
       'ADD P 31', 'P 64 to P 65 LIR'].each do |text|
        expect(rule_ids.call(text)).to include('page_action_heading'), text
      end
    end

    it 'keeps a heading that also prints register values unmapped' do
      ['P 9 Georgia LIR', 'Cyprus REP', 'P 17 International Mobile, shared code ADD1',
       'P  34    Netherlands    89 31 02  (INMO B.V.)    LIR', 'Malta     ADD     278 11   YOM',
       'P 18   Note q)   +883 5140   SUP*'].each do |text|
        expect(rule_ids.call(text)).not_to include('page_action_heading'), text
      end
    end

    it 'excludes column titles in other wordings but not a data row made of ordinary words' do
      expect(rule_ids.call('Pays/zone géographique | MCC + MNC* | Nom de Réseau/Opérateur'))
        .to include('column_header_vocabulary')
      expect(rule_ids.call('Country | ADMD Name | Country code 1 | Service Name(s) | HELPDESK | Contact Address'))
        .to include('column_header_vocabulary')
      expect(rule_ids.call('Mobile Pay Limited | Operator of the network')).not_to include('column_header_vocabulary')
      expect(rule_ids.call('Luxembourg (Country A) | 270 77 | 000 x xxx xxx | Tango S.A.')).to be_empty
    end

    it 'excludes the fixed List VIII questionnaire labels and bulletin cross-references only' do
      expect(rule_ids.call(' 2.      Geographical coordinates')).to include('list_viii_questionnaire_label')
      expect(rule_ids.call('12.     Information available for bandwidth measurements'))
        .to include('list_viii_questionnaire_label')
      expect(rule_ids.call('(Annex to ITU Operational Bulletin No. 1161 – 1.XII.2018)'))
        .to include('bulletin_reference_banner')
      expect(rule_ids.call('1 | 2 | 3 | 4 | 5')).to include('column_header')
      expect(rule_ids.call('Country | Country code | 7')).to be_empty
      expect(rule_ids.call('1.      Name of the station')).to be_empty
      expect(rule_ids.call('(According to Recommendation ITU-T Q.708 (03/1999))'))
        .to include('bulletin_reference_banner')
      expect(rule_ids.call('Associated with shared country code 882, the following two-digit identification code reservations or assignments have been made for the international networks of:'))
        .to include('shared_mcc_intro')
      expect(rule_ids.call('*** As defined in Annex E to Recommendation ITU-T E.212, extra-territorial use of an MCC+MNC is the term used to describe the'))
        .to include('extra_territorial_footnote')
    end
  end

  it 'maps a printed telephone number the patch stores with other grouping' do
    msgs = message('E118_IIN', para('Example Oy Tel: +358 40 866 8582'))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")
    write(File.join(@dir, 'ob/701/e118-iin/001-ADD.yaml'), "type: ADD\ndata:\n  entries:\n  - company_name: Example Oy\n    tel:\n    - \"+358 40 8668582\"\n")
    File.write(File.join(@dir, 'catalog.yaml'), "#{File.read(File.join(@dir, 'catalog.yaml'))}" \
      "- register_id: E118_IIN\n  slug: e118-iin\n  seed_path: datasets/1161-E.118\n")
    _o, err, st = run_script(@env)
    expect(st.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |r| r['text'] }).not_to include('Example Oy Tel: +358 40 866 8582')
  end

  it 'keeps shared-country-code network assignments unmapped without patches' do
    lines = [
      'e            Associated with shared country code 878 for Universal personal telecommunications (UPT), the identification code 10 has been assigned to the network of VISIONng, +878 10.',
      'Associated with shared country code 883, identification code 5140 has been assigned to the network of Example Telecom, +883 5140.'
    ]
    msgs = message('E164_CC', para(*lines))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include(*lines)
  end

  it 'requires full normalized telephone equality while preserving regrouped numbers' do
    lines = ['Example Oy Tel: +358 40 866 85829', 'Example Oy Tel: +999 358 40 866 8582', 'Example Oy Tel: +358 40 866 8582']
    msgs = message('E118_IIN', para(*lines))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")
    write(File.join(@dir, 'ob/701/e118-iin/001-ADD.yaml'), "type: ADD\ndata:\n  company_name: Example Oy\n  tel: '+358 40 8668582'\n")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    unmapped = tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }
    expect(unmapped).to include(*lines.first(2))
    expect(unmapped).not_to include(lines.last)
    expect(tsv(File.join(@out, '100-05-excluded-lines.tsv')).map { |row| row['text'] }).not_to include(lines.last)
  end

  it 'keeps questionnaire answers unmapped until a patch carries the answer without its label' do
    line = '2. Geographical coordinates: 46 N 6 E'
    msgs = message('R_SP_LN.VIII', para(line))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include(line)

    write(File.join(@dir, 'ob/701/list-viii/001-ADD.yaml'), "type: ADD\ndata:\n  coordinates: 46 6 E\n")
    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include(line)

    write(File.join(@dir, 'ob/701/list-viii/001-ADD.yaml'), "type: ADD\ndata:\n  coordinates: 46 N 6 E\n")
    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).not_to include(line)
    expect(tsv(File.join(@out, '100-05-excluded-lines.tsv')).map { |row| row['text'] }).not_to include(line)
  end

  it 'keeps extra-territorial assignment rows unmapped without patches' do
    line = 'Sweden | 240 99 | Example operator assigned extra-territorial use'
    msgs = message('E212_MNC', table_row('Sweden', '240 99', 'Example operator assigned extra-territorial use'))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include(line)
  end

  it 'requires page-heading register values to map while preserving mapped country headings' do
    line = 'P 17 Sweden ADD Example Telecom (carrier code EXAMPLE)'
    heading = 'P 17 Sweden ADD'
    msgs = message('M1400_ICC', para(line, heading))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")
    write(File.join(@dir, 'ob/701/m1400-icc/001-ADD.yaml'), "type: ADD\ndata:\n  country: Sweden\n")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    unmapped = tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }
    expect(unmapped).to include(line)
    expect(unmapped).not_to include(heading)
    expect(tsv(File.join(@out, '100-05-excluded-lines.tsv')).map { |row| row['text'] }).not_to include(heading)
  end

  it 'keeps country-code value rows unmapped without patches' do
    msgs = message('E164_CC', table_row('Country code', '7'))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include('Country code | 7')

    write(File.join(@dir, 'ob/701/e164-cc/001-ADD.yaml'), "type: ADD\ndata:\n  country_code: '7'\n")
    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).not_to include('Country code | 7')
    expect(tsv(File.join(@out, '100-05-excluded-lines.tsv')).map { |row| row['text'] }).not_to include('Country code | 7')
  end

  it 'keeps recommendation references with ISPC assignments unmapped without patches' do
    line = '(According to Recommendation ITU-T Q.708, assign ISPC 2-001-0 to Example Telecom)'
    msgs = message('Q708_ISPC', para(line))
    write(File.join(@dir, 'data/issues/701/amendments.yaml'), "messages:\n#{msgs}")

    _out, err, status = run_script(@env)
    expect(status.success?).to be(true), err
    expect(tsv(File.join(@out, '100-05-unmapped-lines.tsv')).map { |row| row['text'] }).to include(line)
  end
end
