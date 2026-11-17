# frozen_string_literal: true

require 'spec_helper'

# The F.32 (2011) Service Publication reads the register through the ituob
# data provider, not the legacy datasets/980-F.32/data.yaml, which stops at
# ISRAEL. The documents' block and shared table template render here the way
# the metanorma-plugin-lutaml `lutaml_data` block renders them.
RSpec.describe 'F.32 (2011) Service Publication documents' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:dir) { File.join(root, 'documents/T-SP-F.32-2011') }
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

  def render_rows(rows, lang = 'en')
    environment = Liquid::Environment.build do |env|
      env.file_system = Liquid::LocalFileSystem.new(dir, '_%s.liquid')
    end
    source = "{% assign lang = \"#{lang}\" %}{% render \"table\", data: rows, lang: lang %}"
    Liquid::Template.parse(source, environment: environment).render('rows' => rows)
  end

  def row(country, code, name: 'Office', **extra)
    { 'country_or_area' => { 'en' => country, 'fr' => country, 'es' => country },
      'network_roa' => 'ROA', 'network_code' => code[0, 2], 'office_code' => code,
      'telegraph_office_name' => { 'en' => name } }.merge(extra)
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
    expect(render('en').scan('Manama Diplomatic Area Counter').size).to eq(1)
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
      appendix1, appendix2, appendix3 = table.split(/^== Appendix /)[1..]

      expect(appendix1.lines.count { |line| line.start_with?('|') }).to eq(31)
      expect(appendix1).to include('|CA |SV, XQ', '|JP |AA, AB, AS', 'XQ, YL', '|GB |AA, AB, AC')
      expect(appendix2.lines.count { |line| line.match?(/^\|X[A-Z] /) }).to eq(8)
      expect(appendix2).to include('Indicators to be used in the preamble line', 'F.1, A218', 'Banco Internacional de Reconstrucción y Fomento')
      expect(appendix3.lines.count { |line| line.match?(/^\|\d{3} /) }).to eq(27)
      expect(appendix3).to include('|648 |Antigua and Barbuda', '|958 |Madagascar', '|30 | |')
    end
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
    it 'prints the Saudi Arabia shared-indicator footnotes' do
      expect(render('en').scan('The same destination indicator').size).to eq(5)
      expect(render('fr')).to include('Le même indicateur de destination')
    end

    %w[en fr es].each do |lang|
      it "leaves no empty office-name cell in the #{lang} table" do
        expect(render(lang)).not_to match(/^\| *\| [A-Z]{4}(?=footnote|$)/)
      end
    end

    it 'names the offices the printed list leaves blank or in bold' do
      table = render('en')

      expect(edition.items.select { |item| item.telegraph_office_name.nil? || item.telegraph_office_name.en.to_s.strip.empty? }).to be_empty
      expect(table).to match(%r{\| Palo Alto, California Radio/KFS\s*\| URFS})
      expect(table).to match(/\| Mobile, Alabama Radio\s*\| URMO/)
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
