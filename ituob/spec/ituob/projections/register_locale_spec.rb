# frozen_string_literal: true

require 'spec_helper'
require 'liquid'

RSpec.describe Ituob::Projections::RegisterLocale do
  let(:provider) { Ituob::Provider.new }
  let(:locale) { provider.locale(register: 'e212-mnc') }

  def label(key)
    locale.locale.find { |l| l.key == key }
  end

  it 'returns the E.212 labels in English and French from its metadata.yaml' do
    expect(locale).to be_a(Ituob::Models::RegisterLocale)
    expect(locale.locale).to all(be_a(Ituob::Models::LocaleLabel))
    expect(label('networks').en).to eq('Networks')
    expect(label('networks').fr).to eq('Réseaux')
    expect(label('mcc_mnc_codes').fr).to eq('Codes MCC + MNC')
    expect(locale.title).to be_a(Ituob::Models::MultilingualString)
    expect(locale.title.fr).to start_with('Codes de réseau mobile (MNC)')
  end

  it 'keeps every language and the metadata term order' do
    expect(locale.locale.map(&:key)).to eq(%w[country_or_area under_mcc networks mcc_mnc_codes])
    expect(label('country_or_area').to_hash.keys).to match_array(%w[key en fr es zh ru ar])
  end

  it 'round-trips through lutaml-model serialization' do
    expect(Ituob::Models::RegisterLocale.from_yaml(locale.to_yaml)).to eq(locale)
  end

  it 'serves the labels a template reads today, per language' do
    template = Liquid::Template.parse(<<~LIQUID)
      {{ metadata.locale | where: "key", "networks" | map: lang | first }}|{{ metadata.title[lang] | truncate: 20 }}
    LIQUID

    rendered = %w[en fr].map { |lang| template.render('metadata' => locale, 'lang' => lang).strip }

    expect(rendered).to eq(['Networks|Mobile Network Co...', 'Réseaux|Codes de réseau m...'])
  end

  it 'reads the `ch` language key of a metadata.yaml as zh, in title and terms' do
    ispc = provider.locale(register: 'q708-ispc')

    expect(ispc.title.zh).to start_with('国际信令点代码')
    expect(ispc.locale.find { |l| l.key == 'country_or_area' }.zh).to eq('国家/地理区域')
    expect(ispc.locale.map(&:zh)).to all(be_a(String))
  end

  it 'returns an empty term list for a register whose metadata has no locale key' do
    rr251 = provider.locale(register: 'rr251')

    expect(rr251.locale).to eq([])
    expect(rr251.locale.each { nil }).to eq([])
    expect(rr251.title.en).to be_a(String)
  end

  it 'reads a register with a separate seed dataset from its own metadata' do
    shared = provider.locale(register: 'e212-shared-mcc')

    expect(shared.title.en).to match(/Shared Mobile Country Codes/)
  end

  it 'names a register without a seed dataset' do
    expect { provider.locale(register: 'e212-icc') }
      .to raise_error(described_class::MissingMetadataError, /E212_ICC has no seed dataset/)
  end

  it 'rejects an unknown register like the other queries' do
    expect { provider.locale(register: 'nope') }
      .to raise_error(Ituob::Provider::UnknownRegisterError, /Unknown register "nope"/)
  end
end
