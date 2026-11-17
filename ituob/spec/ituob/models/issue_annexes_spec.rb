# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# annexes.yaml is the write path of the annex form: a stored file must come
# back exactly as stored. Comparison is strict (key order, nil, and the
# Time-versus-Date class of position_on), unlike the shared lossless spec
# that ignores nil values.
RSpec.describe Ituob::Models::IssueAnnexes do
  def corpus_files
    Dir.glob(File.join(OB_ISSUES_ROOT, '*', 'annexes.yaml')).sort
  end

  def load_stored(path)
    YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  end

  def exact(hash)
    hash.map do |id, entry|
      [id, entry && entry.map { |key, value| [key, value.class, value] }]
    end
  end

  it 'finds the corpus annex files' do
    expect(corpus_files.length).to be > 250
  end

  it 'returns every stored annexes.yaml exactly (read, then write)' do
    lossy = corpus_files.reject do |path|
      exact(described_class.from_yaml(File.read(path)).to_hash) == exact(load_stored(path))
    end
    expect(lossy).to be_empty
  end

  it 'survives a YAML write and re-read for every stored file' do
    lossy = corpus_files.reject do |path|
      written = described_class.from_yaml(File.read(path)).to_yaml
      exact(described_class.from_yaml(written).to_hash) == exact(load_stored(path))
    end
    expect(lossy).to be_empty
  end

  it 'keeps the annex that carries datasets' do
    path = File.join(OB_ISSUES_ROOT, '1162', 'annexes.yaml')
    annexes = described_class.from_yaml(File.read(path))
    expect(annexes.position_for('E212_MNC').datasets.keys).to eq(load_stored(path).dig('E212_MNC', 'datasets').keys)
  end

  describe 'wire shapes' do
    it 'preserves real __type__ publications while accepting adapter metadata' do
      require 'lutaml/lml'
      [nil, { 'position_on' => Date.new(2018, 12, 15) }].each do |entry|
        data = { '__type__' => entry }
        expect(described_class.from_hash(data).to_hash).to eq(data)
        expect(described_class.from_yaml(data.to_yaml).to_hash).to eq(data)
      end
      parsed = Lutaml::Lml::Format::Adapter::StandardAdapter.parse('instance IssueAnnexes { PUB = instance { position_on = "2018-12-15" } }')
      expect(described_class.from_hash(parsed).publication_ids).to eq(['PUB'])
    end

    it 'preserves numeric and quoted publication identities without lookup collisions' do
      annexes = described_class.from_yaml("1092: {position_on: 2018-12-15}\n'1092': {position_on: 2019-12-15}\n")
      expect(annexes.publication_ids).to eq([1092, '1092'])
      expect(annexes.position_for(1092).position_on).to eq(Date.new(2018, 12, 15))
      expect(annexes.position_for('1092').position_on).to eq(Date.new(2019, 12, 15))
      expect(described_class.from_yaml(annexes.to_yaml).to_hash).to eq(annexes.to_hash)
    end

    it 'preserves yes no on off as distinct publication identifiers' do
      annexes = described_class.from_yaml("yes: null\nno: null\non: null\noff: null\n")
      expect(annexes.publication_ids).to eq(%w[yes no on off])
      expect(annexes.to_hash.keys).to eq(%w[yes no on off])
      expect(described_class.from_yaml(annexes.to_yaml).publication_ids).to eq(%w[yes no on off])
    end

    it 'rejects invalid position types and invalid date text' do
      [true, false, 123, ['2018-12-15'], { 'bad' => 'value' }, 'bogus'].each do |value|
        expect { described_class.from_yaml({ 'PUB' => { 'position_on' => value } }.to_yaml) }
          .to raise_error(ArgumentError, /position_on/)
      end
    end

    it 'preserves null positions and empty mappings as annex events' do
      data = { 'NULL' => nil, 'EMPTY' => {}, 'POSITION' => { 'position_on' => nil }, 'DATASETS' => { 'datasets' => nil } }
      annexes = described_class.from_yaml(data.to_yaml)
      expect(annexes.to_hash).to eq(data)
      expect(described_class.from_yaml(annexes.to_yaml).to_hash).to eq(data)
      expect(annexes.to_hash.select { |_, entry| entry }.keys).to eq(%w[EMPTY POSITION DATASETS])
    end

    it 'returns every stored annexes.yaml byte for byte' do
      changed = corpus_files.reject do |path|
        bytes = File.binread(path)
        described_class.from_yaml(bytes).to_yaml == bytes
      end
      expect(changed).to be_empty
    end

    it 'serializes edits instead of returning stale source bytes' do
      source = "# original formatting\nPUB: {position_on: 2018-12-15, datasets: {en: original}}\n"
      annexes = described_class.from_yaml(source)
      expect(annexes.to_yaml).to eq(source)
      annexes.position_for('PUB').position_on = Date.new(2019, 12, 15)
      annexes.position_for('PUB').datasets['en'] = 'edited'
      reloaded = described_class.from_yaml(annexes.to_yaml)
      expect(reloaded.position_for('PUB').position_on).to eq(Date.new(2019, 12, 15))
      expect(reloaded.position_for('PUB').datasets).to eq('en' => 'edited')
    end

    it 'preserves YAML bytes when loading an IO' do
      source = "# original formatting\nPUB: {position_on: 2018-12-15}\n"
      annexes = described_class.from_yaml(StringIO.new(source))
      expect(annexes.to_yaml).to eq(source)
      expect(annexes.position_for('PUB').position_on).to eq(Date.new(2018, 12, 15))
    end

    it 'reads a timestamp, a date and an unspecified position' do
      annexes = described_class.from_yaml(<<~YAML)
        Q708_ISPC:
          position_on: 2012-03-15T00:00:00.000Z
        E212_MNC:
          position_on: 2018-12-15
        F1_IPTS:
      YAML
      expect(annexes.publication_ids).to eq(%w[Q708_ISPC E212_MNC F1_IPTS])
      expect(annexes.position_for('Q708_ISPC').position_on).to be_a(Time)
      expect(annexes.position_for('E212_MNC').position_on).to be_a(Date)
      expect(annexes.position_for('F1_IPTS').position_on).to be_nil
      expect(annexes.to_hash['F1_IPTS']).to be_nil
    end

    it 'reads an empty file as no annexes' do
      expect(described_class.from_yaml("{}\n").to_hash).to eq({})
      expect(described_class.from_yaml('').to_hash).to eq({})
    end

    it 'rejects keys the corpus does not use' do
      expect { described_class.from_yaml("Q708_ISPC:\n  position: 2012-03-15\n") }
        .to raise_error(ArgumentError, /unknown annex keys \["position"\]/)
    end

    it 'rejects a non-mapping file and a non-mapping position' do
      expect { described_class.from_yaml("- Q708_ISPC\n") }.to raise_error(ArgumentError, /mapping/)
      expect { described_class.from_yaml("Q708_ISPC: 2012-03-15\n") }.to raise_error(ArgumentError, /Q708_ISPC/)
    end
  end
end
