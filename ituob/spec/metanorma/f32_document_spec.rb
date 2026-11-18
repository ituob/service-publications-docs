# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../support/f32_table_structure'

# The F.32 (2011) Service Publication reads the register through the ituob
# data provider, not the legacy datasets/980-F.32/data.yaml, which stops at
# ISRAEL. The documents' block and shared table template render here the way
# the metanorma-plugin-lutaml `lutaml_data` block renders them.
RSpec.describe 'F.32 (2011) Service Publication documents' do
  include F32TableStructure
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:dir) { File.join(root, 'documents/T-SP-F.32-2011') }
  # Official Appendix 1 code membership, pages 41–43.
  let(:origin_indicators) do
    {
      "SJ" => %w[JP],
      "AA" => %w[SV XQ ZZ],
      "WB" => %w[SV],
      "BE" => %w[SV],
      "BR" => %w[BQ SV XQ],
      "CA" => %w[SV XQ],
      "CY" => %w[SU],
      "KR" => %w[SV XQ ZZ MV YQ],
      "EM" => %w[SV XQ],
      "UD" => %w[NX SV XQ],
      "UI" => %w[AW AX BC BQ CS DL FO FS FU GA GH GM GN GX HB JB JX LA LH MA PP PW PX RB RQ SE SS SV SW TD TO TR TW WF WN WU XQ ZZ],
      "UB" => %w[GN SV XQ],
      "UR" => %w[AC AD AI AM AR AS AT AU AW AX AZ BQ BV CA CH CX DB DD DF DL DO DR DV EM ES FC FF FL FS FV GM GN GW HC HT HU IM IN IT IX JX KC LA LC LH LP MA MB MF MI MM MO MP MS MW NA NB NK NL NO NR NT NV PH PM PO PP PR PT PX RQ SD SE SH SI SK SN SP SR SS ST SV TA TL TN TO TP TR TS TU TX UN US VF WB WD WF WL WN WR WT WU WV WW XQ XX YQ],
      "UW" => %w[TC XQ],
      "UF" => %w[FL PR SV XQ],
      "UT" => %w[FL PR SV XQ],
      "FR" => %w[SV XQ],
      "IG" => %w[BB BD DD FF TX],
      "IT" => %w[HQ SV XQ],
      "JP" => %w[AA AB AS CH CR CS DW GN HX KL NA NL NR NT OL OP OU SV TF TL TT TU XQ YL],
      "KT" => %w[SV],
      "LV" => %w[TC],
      "NU" => %w[XQ],
      "NG" => %w[FP SV XQ],
      "UG" => %w[ST SV],
      "PH" => %w[SV XQ],
      "GB" => %w[AA AB AC AD AE AF AG AH AI AJ AK AM AP BC BM CU GC GR GS GW HQ IS LM LX MV PA PB PC PD PH PO PR RV SH SL SV TX UA UB US XQ XX YQ ZZ],
      "SA" => %w[SV XQ]
    }
  end
  # Replaying the register is slow; every example shares one frozen edition and
  # one rendering per language.
  cache = {}
  define_method(:edition) do
    cache[:edition] ||= Ituob::Provider.new(data_root: root).edition(register: 'f32-tdi', as_of: 980)
  end

  define_method(:render) do |lang|
    cache[lang] ||= begin
      environment = Liquid::Environment.build do |env|
        env.file_system = Liquid::LocalFileSystem.new(dir, '_%s.liquid')
      end
      suffix = { 'en' => 'E', 'fr' => 'F', 'es' => 'S' }.fetch(lang)
      source = File.read(File.join(dir, "T-SP-F.32-2011-#{suffix}.adoc")).split('----')[1]
      Liquid::Template.parse(source, environment: environment).render('edition' => edition.to_liquid)
    end
  end


  %w[E F S].each do |suffix|
    it "reads the register from the provider, not the legacy data file, in the #{suffix} document" do
      source = File.read(File.join(dir, "T-SP-F.32-2011-#{suffix}.adoc"))

      expect(source).to include('provider:ituob.edition')
      expect(source).to include('"register":"f32-tdi"')
      expect(source).not_to include('data.yaml')
    end
  end

  it 'renders offices past ISRAEL, where the legacy data stopped' do
    legacy = Ituob::Support::Yaml.safe_load_file(File.join(root, 'datasets/980-F.32/data.yaml'))
    legacy_last = legacy.last.fetch('office_code')
    table = render('en')

    expect(legacy_last).to eq('ILXX')
    expect(table).to include('ZWHX')
    expect(edition.items.map(&:office_code).last).to eq('ZWHX')
  end

  it 'preserves every canonical office while also printing shared office indicators' do
    table = render('en')

    expect(edition.items.map(&:office_code)).to all(satisfy { |code| table.scan(/\| ?#{Regexp.escape(code)}(?=footnote|$)/).size >= 1 })
  end

  it 'renders ambiguous suffixes and shared offices retained outside canonical allocations' do
    expect(render('en')).to include('| --BA', '| --BX', 'Buenos Aires', 'Dacca --> Dhaka')
  end

  it 'keeps canonical membership separate and orders printable contexts by the official source' do
    expect(edition.items.size).to eq(1092)
    canonical_rows = edition.items.map { |entry| [entry.source_row, entry.office_code] }
    printed_rows = edition.printed_items.map { |entry| [entry.source_row, entry.office_code] }
    expect(canonical_rows).to all(satisfy { |key| printed_rows.count(key) == 1 })
    expect(edition.printed_items.count { |entry| !entry.office_code.to_s.empty? }).to eq(1495)
    expect(edition.printed_items.count { |entry| entry.office_code.to_s.start_with?('--') }).to eq(311)
    expect(edition.printed_items.filter_map(&:source_row)).to eq(edition.printed_items.filter_map(&:source_row).sort)
    expect(edition.printed_items.count { |entry| entry.telegraph_office_name&.en == 'Dacca --> Dhaka' }).to eq(1)
    expect(edition.items.find { |entry| entry.office_code == 'BNDP' }.telegraph_office_name.en).to eq('Manama Diplomatic Area Counter')
    expect(render('en')).to include('Manama Diplomatic', 'Area Counter')
    expect(render('en')).to include('remain reserved', 'Unrouted')
  end

  it 'does not publish the original printed contexts as a later replayed edition' do
    catalog = Ituob::Catalogs::Registers.find('F32_TDI')
    state = Ituob::Registers::State.new(register_id: 'F32_TDI', at_ob_issue: 981,
      entries: {}, lapsed_keys: Set.new, deleted_keys: Set.new, history: [])
    later = Ituob::Projections::RegisterEdition.new(register: catalog, state: state,
      items: [], source_contexts: edition.source_contexts).to_model

    expect(later.printed_items).to be_empty
  end

  %w[en fr es].each do |lang|
    it "prints the three official appendices and amendment register in #{lang}" do
      table = render(lang)
      appendix1, appendix2, appendix3 = table.split(/^== (?:Appendix|Appendice|Apéndice) /)[1..]

      appendix_tables, messages = parse_f32_tables(appendix1)
      expect(messages).to be_empty
      expect(appendix_tables.first.rows.body.size).to eq(28)
      expect(appendix1.scan("ÉTATS-UNIS +\nUNITED STATES +\nESTADOS UNIDOS").size).to eq(1)
      expect(appendix1.scan("ITALIE +\nITALY +\nITALIA").size).to eq(1)
      parsed_indicators = appendix_tables.first.rows.body.to_h do |cells|
        [cells[-2].text, cells.last.text.scan(/\b[A-Z]{2}\b/)]
      end
      expect(parsed_indicators).to eq(origin_indicators)
      appendix_tables.first.rows.body.each do |cells|
        groups = cells.last.text.split(/<br>\s*/).map(&:strip)
        expect(groups).to all(match(/\A[A-Z]{2}(?: [A-Z]{2})*\z/))
        expect(groups.map { |group| group.split.map { |code| code[0] }.uniq.size }).to all(eq(1))
      end
      ui_groups = appendix_tables.first.rows.body.find { |cells| cells[-2].text == 'UI' }.last.text
      expect(ui_groups).to include("AW AX<br>\nBC BQ", "FO FS FU")
      expect(table.scan(/^<<<\n\n== (?:Appendix|Appendice|Apéndice) [123]:/).size).to eq(3)
      expect(appendix2.lines.count { |line| line.match?(/^\|X[A-Z] /) }).to eq(8)
      expect(appendix2).to include('Indicators to be used in the preamble line', 'F.1, A218', 'Banco Internacional de Reconstrucción y Fomento')
      expect(appendix3.lines.count { |line| line.match?(/^\|\d{3} /) }).to eq(27)
      expect(appendix3).to include('|648 |Antigua and Barbuda', '|958 |Madagascar', '|30 | |')
    end
  end

  %w[en fr es].each do |lang|
    it "fills five logical columns without dropped cells or escaping rowspans in #{lang}" do
      tables, messages = parse_f32_tables(render(lang).split(/^== (?:Appendix|Appendice|Apéndice) /).first)
      parsed_codes = tables.flat_map do |table|
        table.rows.body.filter_map { |cells| cells.last.text[/\A(?:[A-Z]{4}|--[A-Z]{2})(?=<|footnote|\z)/] }
      end

      expect(messages).to be_empty
      expect(tables).not_to be_empty
      expect(tables.map { |table| table.columns.size }).to all(eq(5))
      expect(tables.flat_map { |table| f32_table_grid_errors(table) }).to be_empty
      expect(parsed_codes.tally).to eq(edition.printed_items.filter_map(&:office_code).tally)
    end
  end

  it "retains every destination source text node in its own edition and page order" do
    codes = edition.items.map(&:office_code)
    { "en" => "", "fr" => "-F", "es" => "-S" }.each do |language, suffix|
      source = Nokogiri::XML(File.read(File.join(root, "ituob/spec/fixtures/f32/official-2011#{suffix}.xml")))
      rows = edition.printed_source_rows.select { |entry| entry.source_language == language }
      expect(rows).not_to be_empty
      expect(rows.map(&:source_page)).to eq(rows.map(&:source_page).sort)
      expect(rows.map(&:source_row)).to eq(rows.map(&:source_row).sort)
      by_page = rows.group_by(&:source_page)
      source.xpath("//page").each do |page|
        next unless by_page.key?(page["number"].to_i)

        retained = normalize_f32_source(by_page.fetch(page["number"].to_i).flat_map(&:source_cells).join(" "), codes)
        page.xpath("./text").each do |node|
          next unless node["top"].to_i > 145 && node["top"].to_i < 1180
          next if node.text.strip.empty?

          expected = normalize_f32_source(node.text.strip, codes)
          expect(retained).to include(expected), "Missing source #{language} p#{page['number']}: #{node.text}"
        end
      end
    end
  end

  it 'keeps a noted country rowspan intact when a translated label differs' do
    first = row('AAA', 'AAAA', network_code_note: { 'fr' => 'Note' },
                country_or_area: { 'en' => 'AAA', 'fr' => 'Pays AAA', 'es' => 'AAA' })
    second = row('AAA', 'AAAB', country_or_area: { 'en' => 'AAA', 'fr' => 'Pays AAA)', 'es' => 'AAA' })
    tables, messages = parse_f32_tables(render_rows([first, second], 'fr'))

    expect(messages).to be_empty
    expect(tables.size).to eq(1)
    expect(tables.flat_map { |table| f32_table_grid_errors(table) }).to be_empty
    expect(tables.first.rows.body.drop(2).first.first.text).to include('Pays AAA', 'AAA')
    expect(tables.first.rows.body.drop(2).map { |cells| cells.last.text }).to eq(%w[AAAA AAAB])
  end

  it 'keeps distinct countries separate when their translated labels match' do
    first = row('AAA', 'AAAA')
    second = row('BBB', 'BBAA', country_or_area: { 'en' => 'BBB', 'fr' => 'AAA', 'es' => 'BBB' })
    tables, messages = parse_f32_tables(render_rows([first, second], 'fr'))

    expect(messages).to be_empty
    expect(tables.flat_map { |table| f32_table_grid_errors(table) }).to be_empty
    expect(tables.first.rows.body.drop(2).map { |cells| cells.first.text }).to include(
      a_string_including('AAA'), a_string_including('BBB'))
    expect(tables.first.rows.body.drop(2).map { |cells| cells.last.text }).to eq(%w[AAAA BBAA])
  end

  it 'prints two-letter network codes in the printed network form' do
    expect(render('en')).to match(/^\s*\| AF- -$/)
    expect(render('en')).to include('[cols="24,28,12,26,10",options="unnumbered"]')
  end

  it 'localises the table heading and column headers' do
    expect(render('fr')).to include('Indicateurs de destination (ID) attribués aux bureaux télégraphiques',
                                    'Code de bureau')
    expect(render('es')).to include('Indicadores de destino (ID) atribuidos a oficinas telegráficas')
  end

  describe 'content the table must not lose' do
    let(:printed_content) do
      JSON.parse(File.read(File.join(root, 'ituob/spec/fixtures/f32/printed-content.json')))
    end

    it 'pins the independent content oracle to the official PDF' do
      path = File.join(root, 'ituob/spec/fixtures/f32/official-2011.pdf')
      expect(Digest::SHA256.file(path).hexdigest).to eq(printed_content.fetch('official_sha256'))
      expect(printed_content.fetch('notes').size).to eq(35)
    end

    %w[en fr es].each do |lang|
      it "preserves all 35 complete printed cessation notes in #{lang}" do
        destination = render(lang).split(/^== (?:Appendix|Appendice|Apéndice) /).first
        normalized = destination.downcase.gsub(/[^\p{Alnum}]/, '')

        printed_content.fetch('notes').each do |note|
          expected = note.fetch(lang).downcase.gsub(/[^\p{Alnum}]/, '')
          expect(normalized).to include(expected), "Missing complete #{lang} cessation note from official page #{note.fetch('page')}"
        end
      end

      it "keeps reservation countries in printed order and network cells in #{lang}" do
        destination = render(lang).split(/^== (?:Appendix|Appendice|Apéndice) /).first
        countries = destination.scan(/^\s*\|\s*\*([^*]+)\*/).flatten
        expected_order = printed_content.fetch('countries')

        # Adjacent equal labels are the official three-language heading.
        headings = countries.join(' ').gsub(/\s+/, ' ')
        positions = expected_order.map { |country| headings.index(country) }
        expect(positions).not_to include(nil)
        expect(positions).to eq(positions.sort)
        printed_content.fetch('network_codes').each do |code|
          expect(destination).to match(/\| #{code}(?:- -|\s+- -)/)
        end
      end
    end

    it 'prints the Saudi Arabia shared-indicator footnotes without changing the canonical notes' do
      canonical_legends = edition.items.sum { |entry| entry.notes&.en.to_s.scan('Seasonal Opening').size }
      expect(canonical_legends).to eq(6)
      expect(render('en').scan('The same destination indicator').size).to eq(5)
      expect(render('fr')).to include('Le même indicateur de destination')
    end

    { 'en' => 'Seasonal Opening', 'fr' => 'Ouverture saisonnière', 'es' => 'Apertura estacional' }.each do |lang, legend|
      it "prints the Saudi shared office legend once in #{lang}" do
        expect(render(lang).scan(legend).size).to eq(1)
        expect(render(lang)).to include('Uwaqilah', 'Zalim', 'Suq Al Arab Mina', 'Yedemah', 'Zilfi')
      end
    end

    %w[en fr es].each do |lang|
      it "leaves only the official US coast-station continuation names blank in #{lang}" do
        tables, messages = parse_f32_tables(render(lang).split(/^== (?:Appendix|Appendice|Apéndice) /).first)
        blank_names = tables.flat_map do |table|
          table.rows.body.filter_map do |cells|
            code = cells.last.text[/\A[A-Z]{4}\z/]
            code if code && cells[-2].text.strip.empty?
          end
        end

        expect(messages).to be_empty
        expect(render(lang)).not_to match(/footnote:\[\s*\]/)
        expect(blank_names.sort).to eq(%w[UJMR URFS URMO UTFS UTMR])
        expect(render(lang).scan('Mobile, Alabama Radio').size).to eq(1)
        expect(render(lang).scan('Palo Alto, California Radio/KFS').size).to eq(1)
      end
    end

    it 'names the offices the printed list leaves blank or in bold' do
      table = render('en')

      expect(edition.items.select { |item| item.telegraph_office_name.nil? || item.telegraph_office_name.en.to_s.strip.empty? }).to be_empty
      expect(table).to include('Palo Alto, California', 'Radio/KFS', '| UIMS')
      expect(table).to include('Mobile, Alabama Radio', '| UIMR')
      expect(edition.items.find { |entry| entry.office_code == 'URMO' }.telegraph_office_name.en).to eq('Mobile, Alabama Radio')
      expect(table).to match(/\| ADEN\s*\| YDAN/)
    end

    it 'prints French and Spanish names for the offices whose legacy names differ from English' do
      legacy = Ituob::Support::Yaml.safe_load_file(File.join(root, 'datasets/980-F.32/data.yaml'))
      by_code = legacy.group_by { |entry| entry['office_code'] }
      carried = edition.items.select do |item|
        legacy_name = by_code.fetch(item.office_code, []).map { |entry| entry['telegraph_office_name'] }.compact
                              .find { |name| name['en'].to_s.strip.casecmp?(item.telegraph_office_name.en.to_s.strip) }
        legacy_name && legacy_name['fr'].to_s.strip != legacy_name['en'].to_s.strip
      end

      expect(carried.size).to be >= 70
      expect(carried).to all(satisfy { |item| item.telegraph_office_name.fr.to_s.strip != '' })
      sample = carried.first
      expect(render('fr')).to include(sample.telegraph_office_name.fr)
    end

    it 'gives each contiguous country run its own rowspan' do
      table = render_rows([row('AAA', 'AAAA'), row('AAA', 'AAAB'), row('BBB', 'BBAA'), row('AAA', 'AAAC')])

      expect(table.scan(/^\.(\d+)\+/).flatten).to eq(%w[2 1 1])
    end

    it 'keeps rowspans when an item has no country' do
      table = render_rows([row('AAA', 'AAAA'), row('AAA', 'AAAB'), { 'office_code' => 'ZZZZ' }, row('BBB', 'BBAA')])

      expect(table.scan(/^\.(\d+)\+/).flatten).to include('2')
    end

    %w[INDIA AUSTRALIA].each do |country|
      it "keeps the country column for #{country} context rows without a subarea" do
        table = render_rows([row(country, 'AAAA'), row(country, '--BX')])

        expect(table.lines.count { |line| line.strip == '|' }).to eq(2)
      end
    end

    it 'escapes a pipe in an office name' do
      table = render_rows([row('AAA', 'AAAA', name: 'Left | Right')])

      expect(table).to include('| Left \\| Right')
    end

    it 'strips only a trailing 1) from a country name' do
      table = render_rows([row('AUSTRALIA1)', 'AAAA'), row('PORT 1) ISLAND', 'BBAA')])

      expect(table).to include('*AUSTRALIA*', '*PORT 1) ISLAND*')
    end
  end
end
