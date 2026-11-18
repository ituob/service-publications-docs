# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::Provider, 'typed publication datasets' do
  let(:provider) { described_class.new }

  Ituob::Projections::PublicationDataset::DATASETS.each do |dataset, model_name|
    it "preserves every ordered #{dataset} row through its typed LML model" do
      source = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', dataset, 'data.yaml'))
      publication = provider.publication(dataset: dataset, as_of: dataset.to_i)

      expect(publication).to be_a(Ituob::Models::PublicationDataset)
      expect(publication.dataset).to eq(dataset)
      expect(publication.as_of_issue).to eq(dataset.to_i)
      expect(publication.items).to all(be_a(Ituob::Models.const_get(model_name)))
      expect(publication.items.map { |item| item.to_hash.reject { |key, _| key == '_class' } }).to eq(source)

      metadata = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', dataset, 'metadata.yaml'))
      expect(publication.metadata.title.to_hash).to eq(metadata.fetch('title'))
      expected_labels = Ituob::Projections::PublicationLabels.for_dataset(dataset, Ituob::Models::PublicationMetadata.from_hash(metadata))
      expect(Array(publication.metadata.locale).map(&:to_hash)).to eq(Array(expected_labels.locale).map(&:to_hash))
    end
  end

  it 'preserves numeric frequencies and nested translated tone notes' do
    rows = provider.publication(dataset: '955-E.180', as_of: 955).items
    expect(rows.first.frequency_in_hz).to be_a(Integer)
    expect(rows.map(&:frequency_in_hz)).to include(a_kind_of(String))
    note = rows.find { |row| row.tone_desc&.notes }
    expect(note.tone_desc.notes.en).not_to be_empty
  end

  it 'returns multiple typed datasets in requested order, including six-language labels' do
    names = %w[1117-E.212A-MCCMNC 1117-E.212A]
    publication = provider.publication(datasets: names, as_of: 1117)
    expect(publication.sources.map(&:dataset)).to eq(names)
    restored = Ituob::Models::PublicationDatasets.from_hash(publication.to_hash)
    expect(restored.sources.last.items.first).to be_a(Ituob::Models::PublicationE212AEntry)
    labels = publication.sources.last.metadata.locale.find { |label| label.key == 'code' }
    expect(labels.to_hash.keys).to include('en', 'fr', 'es', 'ar', 'ru', 'zh')
    template = Liquid::Template.parse("{% assign source = edition.sources | where: 'dataset', '1117-E.212A' | first %}{{ source.items.first.code }}|{{ source.metadata.title.ru }}")
    expect(template.render!('edition' => publication.to_liquid)).to eq("0XX|#{publication.sources.last.metadata.title.ru}")
  end

  it 'preserves the RR251 country sidecars and scalar notes without hashes as model attributes' do
    publication = provider.publication(dataset: '1154-RR.25.1', as_of: 1154)
    countries = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1154-RR.25.1', 'countries.yaml'))
    expect(publication.countries.map { |country| country.to_hash.reject { |key, _| key == 'data' } }).to eq(countries)
    publication.countries.each do |country|
      data = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1154-RR.25.1', 'data', "#{country.key}.yaml"))
      expect(country.data.to_hash).to eq(data)
    end
    expect(publication.items.flat_map(&:notes).compact).to all(be_a(String))
  end

  it 'preserves T35B scalar lists and the typed acronym lookup' do
    publication = provider.publication(dataset: '1001-T.35B', as_of: 1001)
    authority = publication.items.first.assignment_authority.first
    expect(authority.terminal_type).to all(be_a(String))
    expect(authority.related_links).to all(be_a(String))
    source = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1001-T.35B', 'acronyms.yaml'))
    expect(publication.acronyms.to_hash).to eq(source.transform_keys(&:to_s))
  end

  it 'preserves value equality for Liquid map and uniq on translated countries and fields' do
    { '1117-E.212A' => 'country_or_area', '669-F.1' => 'field_desc' }.each do |dataset, field|
      publication = provider.publication(dataset: dataset, as_of: dataset.to_i)
      source = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', dataset, 'data.yaml'))
      template = Liquid::Template.parse("{{ data | map: '#{field}' | uniq | size }}")
      expect(template.render!('data' => publication.to_liquid['items'])).to eq(template.render!('data' => source))
    end
  end

  it 'preserves Liquid pair iteration over service restrictions' do
    publication = provider.publication(dataset: '1000-SR.1', as_of: 1000)
    source = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1000-SR.1', 'data.yaml'))
    template = Liquid::Template.parse('{% for row in data %}{% for call in row.restrictions.no_collect_calls %}{{ call[0] }}={{ call[1] }};{% endfor %}{% endfor %}')
    expect(template.render!('data' => publication.to_liquid['items'])).to eq(template.render!('data' => source))
  end

  it 'preserves Liquid equality between amateur and experimental radio call sign groups' do
    publication = provider.publication(dataset: '1154-RR.25.1', as_of: 1154)
    source = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1154-RR.25.1', 'countries.yaml'))
    source.each do |country|
      country['data'] = Ituob::Support::Yaml.safe_load_file(Ituob::DataRoot.join('datasets', '1154-RR.25.1', 'data', "#{country.fetch('key')}.yaml"))
    end
    template = Liquid::Template.parse('{% for country in countries %}{% if country.data.groups.amateur == country.data.groups.experimental %}{{ country.key }};{% endif %}{% endfor %}')
    expect(template.render!('countries' => publication.to_liquid['countries'])).to eq(template.render!('countries' => source))
  end

  it 'rejects unknown, traversing or mismatched dataset selectors' do
    expect { provider.publication(dataset: '../955-E.180', as_of: 955) }.to raise_error(ArgumentError, /Unknown publication dataset/)
    expect { provider.publication(dataset: '955-E.180', as_of: 956) }.to raise_error(ArgumentError, /only available at issue 955/)
    expect { provider.publication(dataset: '955-E.180', as_of: '955junk') }.to raise_error(ArgumentError)
    expect { provider.publication(dataset: '955-E.180', register: 'e180', as_of: 955) }.to raise_error(ArgumentError, /exactly one/)
    expect { provider.publication(datasets: [], as_of: 955) }.to raise_error(ArgumentError)
    expect { provider.publication(datasets: %w[955-E.180 955-E.180], as_of: 955) }.to raise_error(ArgumentError)
    expect { provider.publication(as_of: 955) }.to raise_error(ArgumentError, /exactly one/)
  end

  context 'when a publication source adds an unsupported field' do
    around do |example|
      original = Ituob::DataRoot.path
      Dir.mktmpdir do |root|
        %w[catalogs ob-issues].each { |name| File.symlink(File.join(original, name), File.join(root, name)) }
        path = File.join(root, 'datasets', '955-E.180')
        FileUtils.mkdir_p(path)
        %w[data.yaml metadata.yaml].each { |name| FileUtils.cp(File.join(original, 'datasets', '955-E.180', name), File.join(path, name)) }
        Ituob::DataRoot.configure(root)
        example.run
      ensure
        Ituob::DataRoot.configure(nil)
      end
    end

    it 'rejects a lost nested field before returning a publication' do
      path = Ituob::DataRoot.join('datasets', '955-E.180', 'data.yaml')
      data = Ituob::Support::Yaml.safe_load_file(path)
      data.first.fetch('tone_desc')['unmodeled'] = 'preserve this'
      File.write(path, data.to_yaml)
      expect { provider.publication(dataset: '955-E.180', as_of: 955) }.to raise_error(ArgumentError, /955-E.180.*row 1.tone_desc.unmodeled/)
    end

    it 'accepts the historical Chinese metadata alias without dropping the translation' do
      path = Ituob::DataRoot.join('datasets', '955-E.180', 'metadata.yaml')
      data = Ituob::Support::Yaml.safe_load_file(path)
      data.fetch('title')['ch'] = '中文'
      File.write(path, data.to_yaml)
      expect(provider.publication(dataset: '955-E.180', as_of: 955).metadata.title.zh).to eq('中文')
    end

    it 'rejects empty metadata labels' do
      path = Ituob::DataRoot.join('datasets', '955-E.180', 'metadata.yaml')
      File.write(path, { 'title' => {}, 'locale' => [] }.to_yaml)
      expect { provider.publication(dataset: '955-E.180', as_of: 955) }.to raise_error(ArgumentError, /invalid publication metadata/)
    end

    it 'rejects an unknown metadata language' do
      path = Ituob::DataRoot.join('datasets', '955-E.180', 'metadata.yaml')
      data = Ituob::Support::Yaml.safe_load_file(path)
      data.fetch('title')['unknown'] = 'preserve this'
      File.write(path, data.to_yaml)
      expect { provider.publication(dataset: '955-E.180', as_of: 955) }.to raise_error(ArgumentError, /955-E.180.*metadata.title.unknown/)
    end
  end
end
