# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'digest'
require_relative '../../../scripts/merge_publication_manifests'

RSpec.describe MergePublicationManifests do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  def shard(name, standard, langs, log: '', bytes: nil)
    base = File.join(@dir, 'parts', name)
    entries = langs.map do |lang|
      path = "pdf/#{standard}-2011/#{standard}-2011-#{lang}.pdf"
      FileUtils.mkdir_p(File.dirname(File.join(base, path)))
      File.write(File.join(base, path), bytes || "#{standard}#{lang}")
      { 'standard' => standard, 'edition_year' => 2011, 'language' => lang,
        'sha256' => Digest::SHA256.hexdigest("#{standard}#{lang}"), 'path' => path }
    end
    File.write(File.join(base, 'pdf', 'manifest.json'), JSON.generate('publications' => entries))
    File.write(File.join(base, 'render-failures.log'), log)
  end

  let(:parts) { File.join(@dir, 'parts') }
  let(:out) { File.join(@dir, 'out') }

  it 'writes one sorted manifest at the root and the PDFs at the paths it names' do
    shard('b', 'B.2', %w[es en])
    shard('a', 'A.1', %w[en])
    described_class.merge(parts: parts, out: out, expect: 2)
    list = JSON.parse(File.read(File.join(out, 'manifest.json'))).fetch('publications')
    expect(list.map { |e| [e['standard'], e['language']] }).to eq([%w[A.1 en], %w[B.2 en], %w[B.2 es]])
    expect(list.map { |e| File.size?(File.join(out, e['path'])) }).to all(be_truthy)
  end

  it 'fails and writes nothing when a shard logged a render failure' do
    shard('a', 'A.1', %w[en], log: "x.adoc: metanorma exit 1\n")
    expect { described_class.merge(parts: parts, out: out) }.to raise_error(described_class::Error, /render failures/)
    expect(File.exist?(out)).to be(false)
  end

  it 'fails when a PDF does not match its sha256' do
    shard('a', 'A.1', %w[en], bytes: 'tampered')
    expect { described_class.merge(parts: parts, out: out) }.to raise_error(described_class::Error, /sha256 mismatch/)
  end

  it 'fails when a shard is missing' do
    shard('a', 'A.1', %w[en])
    expect { described_class.merge(parts: parts, out: out, expect: 2) }.to raise_error(described_class::Error, /expected 2 shards/)
  end

  it 'fails on two entries for one edition' do
    shard('a', 'A.1', %w[en])
    shard('b', 'A.1', %w[en])
    expect { described_class.merge(parts: parts, out: out) }.to raise_error(described_class::Error, /duplicate/)
  end
end
