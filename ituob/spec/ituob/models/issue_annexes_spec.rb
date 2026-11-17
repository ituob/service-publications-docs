# frozen_string_literal: true

require 'spec_helper'

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
