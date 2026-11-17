# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::Provider, 'publication data integrity' do
  let(:register) { Ituob::Catalogs::Registers.find('E118_IIN') }
  let(:provider) { described_class.new(data_root: @temporary_root) }
  let(:seed_path) { File.join(@temporary_root, register.seed_path, 'data.yaml') }
  let(:metadata_path) { File.join(@temporary_root, register.seed_path, 'metadata.yaml') }
  let(:publication) { provider.publication(register: register.slug, as_of: register.seed_issue) }

  around do |example|
    Dir.mktmpdir do |root|
      @temporary_root = root
      %w[catalogs ob-issues].each do |directory|
        File.symlink(Ituob::DataRoot.join(directory), File.join(root, directory))
      end
      dataset = File.join(root, register.seed_path)
      FileUtils.mkdir_p(dataset)
      %w[data.yaml metadata.yaml].each do |filename|
        FileUtils.cp(Ituob::DataRoot.join(register.seed_path, filename), File.join(dataset, filename))
      end
      example.run
    ensure
      Ituob::DataRoot.configure(nil)
    end
  end

  { 'missing' => :missing, 'empty file' => '', 'null' => "null\n", 'mapping' => "{}\n",
    'scalar' => "false\n", 'empty list' => "[]\n", 'null row' => "- null\n",
    'empty row' => "- {}\n", 'scalar row' => "- text\n" }.each do |shape, content|
    it "rejects a #{shape} publication seed with a register-specific error" do
      content == :missing ? File.unlink(seed_path) : File.write(seed_path, content)
      expect { publication }.to raise_error(ArgumentError, /E118_IIN.*(?:seed|row)/)
    end
  end

  { 'missing' => :missing, 'empty file' => '', 'null' => "null\n", 'empty mapping' => "{}\n",
    'list' => "[]\n",
    'empty title' => "title: {}\nlocale: [{key: code, en: Code}]\n",
    'null label' => "title: {en: Title}\nlocale: [null]\n",
    'unkeyed label' => "title: {en: Title}\nlocale: [{en: Code}]\n" }.each do |shape, content|
    it "rejects #{shape} publication metadata with a register-specific error" do
      content == :missing ? File.unlink(metadata_path) : File.write(metadata_path, content)
      expect { publication }.to raise_error(ArgumentError, /E118_IIN.*metadata/)
    end
  end

  %w[title locale].each do |field|
    it "rejects an unmodeled metadata language in #{field}" do
      metadata = YAML.safe_load_file(metadata_path)
      labels = field == 'title' ? metadata.fetch(field) : metadata.fetch(field).first
      labels['unmodeled_language'] = 'Must not disappear'
      File.write(metadata_path, metadata.to_yaml)

      expect { publication }.to raise_error(ArgumentError, /E118_IIN.*metadata.*unmodeled_language/)
    end
  end

  it 'rejects a null-only seed row' do
    File.write(seed_path, [{ 'country_or_area' => nil }].to_yaml)
    expect { publication }.to raise_error(ArgumentError, /E118_IIN.*row 1.*content/)
  end

  it 'preserves a valid row with an optional null field' do
    row = { 'country_or_area' => { 'en' => 'Example' }, 'company_name' => nil }
    File.write(seed_path, [row].to_yaml)
    expect(publication.items.first.to_hash.fetch('country_or_area')).to eq('en' => 'Example')
  end

  it 'rejects a null-only title' do
    File.write(metadata_path, { 'title' => { 'en' => nil } }.to_yaml)
    expect { publication }.to raise_error(ArgumentError, /E118_IIN.*metadata.*content/)
  end

  %w[title locale].each do |field|
    [%w[ch zh], %w[zh ch]].each do |languages|
      it "rejects conflicting Chinese aliases in #{field} ordered #{languages.join('/')}" do
        labels = languages.zip(['First title', 'Second title']).to_h
        metadata = field == 'title' ? { 'title' => labels } :
          { 'title' => { 'en' => 'Title' }, 'locale' => [labels.merge('key' => 'code')] }
        File.write(metadata_path, metadata.to_yaml)
        expect { publication }.to raise_error(ArgumentError, /E118_IIN.*metadata.*(?:ch|zh)/)
      end
    end
  end

  it 'preserves an unambiguous Chinese alias and equal aliases' do
    File.write(metadata_path, { 'title' => { 'ch' => 'Title' },
      'locale' => [{ 'key' => 'code', 'ch' => 'Code', 'zh' => 'Code' }] }.to_yaml)
    expect(publication.metadata.to_hash).to include(
      'title' => { 'zh' => 'Title' }, 'locale' => [{ 'key' => 'code', 'zh' => 'Code' }]
    )
  end

  it 'allows metadata with no optional locale labels' do
    File.write(metadata_path, { 'title' => { 'en' => 'Publication title' } }.to_yaml)
    expect(publication.metadata.title.en).to eq('Publication title')
    expect(publication.metadata.locale).to be_empty
  end

  it 'rejects meaningful seed fields that the compiled model would discard' do
    rows = YAML.safe_load_file(seed_path)
    rows.first['unmodeled_publication_note'] = 'Must not disappear'
    File.write(seed_path, rows.to_yaml)

    expect { publication }.to raise_error(ArgumentError, /E118_IIN.*unmodeled_publication_note/)
  end

  it 'rejects meaningful nested seed fields that the compiled model would discard' do
    rows = YAML.safe_load_file(seed_path)
    rows.first['country_or_area']['unmodeled_language'] = 'Must not disappear'
    File.write(seed_path, rows.to_yaml)

    expect { publication }.to raise_error(ArgumentError, /E118_IIN.*country_or_area.unmodeled_language/)
  end
end

RSpec.describe Ituob::Provider, 'valid publication preservation' do
  %w[E118_IIN E218_TRCC M1400_ICC E164_ACN DP X121_DNIC F400_ADMD Q708_ISPC Q708_SANC
     E164_CC E164_NOTE_N E164_NOTE_O E164_NOTE_PQ].each do |id|
    it "preserves every ordered #{id} seed row and its localized metadata" do
      register = Ituob::Catalogs::Registers.find(id)
      rows = YAML.safe_load_file(Ituob::DataRoot.join(register.seed_path, 'data.yaml'))
      edition = described_class.new.publication(register: id, as_of: register.seed_issue)

      expect(edition.items.size).to eq(rows.size)
      rows.zip(edition.items).each do |row, item|
        expect(item.to_hash).to include(row)
      end
      expect(edition.metadata.to_hash).to eq(described_class.new.locale(register: id).to_hash)
    end
  end
end
