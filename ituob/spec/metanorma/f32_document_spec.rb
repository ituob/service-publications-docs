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
      source = "{% assign lang = \"#{lang}\" %}{% render \"table\", data: edition.items, lang: lang %}"
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

  it 'renders every register office exactly once in the English table' do
    table = render('en')

    expect(edition.items.map(&:office_code)).to all(satisfy { |code| table.scan(/\| ?#{Regexp.escape(code)}(?=footnote|$)/).size == 1 })
  end

  it 'prints two-letter network codes in the printed network form' do
    expect(render('en')).to match(/^\s*\| AF- -$/)
  end

  it 'localises the table heading and column headers' do
    expect(render('fr')).to include('Indicateurs de destination (ID) attribués aux bureaux télégraphiques',
                                    'Code de bureau')
    expect(render('es')).to include('Indicadores de destino (ID) atribuidos a oficinas telegráficas')
  end
end
