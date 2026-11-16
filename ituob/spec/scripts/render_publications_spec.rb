# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'digest'
require_relative '../../../scripts/render_publications'

RSpec.describe RenderPublications do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  SITE_KEYS = %w[standard title edition_year language as_of_issue sha256 status register_slugs path].freeze

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def doc(dir, lang, dataset)
    write("documents/#{dir}/#{dir}-#{lang}.adoc", <<~ADOC)
      = Title
      :docnumber: x

      [yaml2text,data=../../datasets/#{dataset}/data.yaml,metadata=../../datasets/#{dataset}/metadata.yaml]
      ----
      x
      ----
    ADOC
  end

  before do
    write('catalogs/registers.yaml', <<~YAML)
      registers:
        - register_id: E118_IIN
          slug: e118-iin
          seed_issue: 1161
          seed_path: datasets/1161-E.118
    YAML
    write('datasets/1161-E.118/data.yaml', "- a: 1\n")
    write('datasets/1161-E.118/metadata.yaml', "title:\n  en: Issuer identification\n  fr: Identification des emetteurs\n")
    write('datasets/991-PP.RES.21.pp/data.yaml', "- a: 1\n")
    write('datasets/991-PP.RES.21.pp/metadata.yaml', "title:\n  en: Call-Back\n")
    write('datasets/NOISSUE/metadata.yaml', "title:\n  en: No issue\n")
    doc('T-SP-E.118-2018', 'E', '1161-E.118')
    doc('T-SP-E.118-2018', 'F', '1161-E.118')
    doc('T-SP-E.118-2018', 'S', '1161-E.118') # no Spanish title in the metadata
    doc('T-SP-PP.RES.21-2011', 'E', '991-PP.RES.21.pp')
    doc('T-SP-E.164B-2012', 'E', 'NOISSUE')
  end

  let(:out_dir) { File.join(@root, 'build') }
  # Stands in for metanorma: writes the PDF beside the source, or fails for F.
  let(:renderer) do
    lambda do |adoc|
      return [nil, 'boom'] if adoc.end_with?('-F.adoc') && adoc.include?('PP.RES.21')

      pdf = adoc.sub(/\.adoc\z/, '.pdf')
      File.binwrite(pdf, "%PDF fake #{File.basename(adoc)}")
      [pdf, nil]
    end
  end

  def run_render(**opts)
    described_class.run(root: @root, out_dir: out_dir, renderer: renderer, **opts)
  end

  def manifest_json
    JSON.parse(File.read(File.join(out_dir, 'pdf', 'manifest.json')))
  end

  it 'writes the manifest with the site field names, checksum of the copied bytes and deterministic path' do
    run_render(docs: ['T-SP-E.118-2018'], langs: %w[E F])
    entries = manifest_json.fetch('publications')
    expect(entries.size).to eq(2)
    en = entries.find { |e| e['language'] == 'en' }
    expect(en).to include(
      'standard' => 'E.118', 'recommendation' => 'E.118', 'title' => 'Issuer identification',
      'edition_year' => 2018, 'as_of_issue' => 1161, 'status' => 'candidate',
      'register_slugs' => ['e118-iin'], 'path' => 'pdf/E.118-2018/E.118-2018-E.pdf'
    )
    expect(SITE_KEYS - en.keys).to eq([])
    expect(en['sha256']).to eq(Digest::SHA256.file(File.join(out_dir, en['path'])).hexdigest)
    expect(en['sha256']).to match(/\A\h{64}\z/)
  end

  it 'leaves failed renders out of the manifest and logs each with its reason' do
    result = run_render
    files = result.failures.to_h { |f| [f.file, f.reason] }
    expect(files.keys).to contain_exactly(
      'T-SP-E.118-2018-S.adoc', 'T-SP-E.164B-2012-E.adoc'
    )
    expect(files['T-SP-E.164B-2012-E.adoc']).to match(/no numbered dataset/)
    expect(files['T-SP-E.118-2018-S.adoc']).to match(/no title for es/)
    expect(manifest_json['publications'].map { |e| e['path'] }).to eq(
      ['pdf/E.118-2018/E.118-2018-E.pdf', 'pdf/E.118-2018/E.118-2018-F.pdf', 'pdf/PP.RES.21-2011/PP.RES.21-2011-E.pdf']
    )
    expect(File.read(File.join(out_dir, 'render-failures.log'))).to include('T-SP-E.164B-2012-E.adoc: no numbered dataset')
  end

  it 'logs a renderer failure and omits that language' do
    failing = described_class.run(root: @root, out_dir: out_dir, docs: ['T-SP-PP.RES.21-2011'], langs: %w[E F],
                                  renderer: ->(adoc) { adoc.end_with?('-E.adoc') ? [nil, 'boom'] : [nil, 'no file'] })
    expect(failing.failures.map(&:reason)).to eq(['boom'])
    expect(manifest_json['publications']).to eq([])
  end

  it 'emits register_slugs as an empty array for a publication without a register (the site rejects a missing array)' do
    run_render(docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
    entry = manifest_json['publications'].first
    expect(entry['register_slugs']).to eq([])
    expect(entry['as_of_issue']).to eq(991)
  end

  it 'defaults to candidate and reads a per-publication status file' do
    write('documents/T-SP-E.118-2018/publication-status.yaml', "status: itu-adopted\n")
    run_render(docs: ['T-SP-E.118-2018', 'T-SP-PP.RES.21-2011'], langs: ['E'])
    expect(manifest_json['publications'].to_h { |e| [e['standard'], e['status']] }).to eq(
      'E.118' => 'itu-adopted', 'PP.RES.21' => 'candidate'
    )
  end

  it 'rejects an invalid status as a failed entry rather than publishing it' do
    write('documents/T-SP-E.118-2018/publication-status.yaml', "status: official\n")
    result = run_render(docs: ['T-SP-E.118-2018'], langs: ['E'])
    expect(result.failures.map(&:reason).first).to match(/invalid status "official"/)
    expect(manifest_json['publications']).to eq([])
  end

  it 'rejects an unknown publication name' do
    expect { run_render(docs: ['T-SP-NOPE-2000']) }.to raise_error(ArgumentError, /unknown publication/)
  end

  it 'derives the Recommendation by dropping one trailing letter after a digit' do
    expect(%w[E.164B X.121A T.35B E.118 M.1400 RR.25.1 PP.RES.21 SR.1].map { |s| described_class.recommendation(s) })
      .to eq(%w[E.164 X.121 T.35 E.118 M.1400 RR.25.1 PP.RES.21 SR.1])
  end

  it 'is deterministic: a rerun on the same data gives a byte-identical manifest' do
    run_render(docs: ['T-SP-E.118-2018'], langs: %w[E F])
    first = File.read(File.join(out_dir, 'pdf', 'manifest.json'))
    run_render(docs: ['T-SP-E.118-2018'], langs: %w[E F])
    expect(File.read(File.join(out_dir, 'pdf', 'manifest.json'))).to eq(first)
  end
end
