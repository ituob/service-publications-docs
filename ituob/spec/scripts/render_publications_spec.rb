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

  describe 'fail closed' do
    def reasons(result)
      result.failures.to_h { |f| [f.file, f.reason] }
    end

    def run_with(renderer, **opts)
      described_class.run(root: @root, out_dir: out_dir, renderer: renderer, **opts)
    end

    it 'turns a raising renderer into a failed entry and still writes the manifest and log' do
      calls = 0
      raising = lambda do |adoc|
        calls += 1
        raise 'renderer blew up' if calls == 1

        pdf = adoc.sub(/\.adoc\z/, '.pdf')
        File.binwrite(pdf, 'x')
        [pdf, nil]
      end
      result = run_with(raising, docs: ['T-SP-E.118-2018'], langs: %w[E F])
      expect(reasons(result)['T-SP-E.118-2018-E.adoc']).to eq('RuntimeError: renderer blew up')
      expect(manifest_json['publications'].map { |e| e['language'] }).to eq(['fr'])
      expect(File.read(File.join(out_dir, 'render-failures.log'))).to include('renderer blew up')
    end

    {
      'a list' => "- a\n- b\n",
      'a bare string' => "just a string\n",
      'a ruby object tag' => "status: !ruby/object:Object {}\n",
      'a syntax error' => ": : :\n  - [\n",
      'an empty file' => '',
      'status false' => "status: false\n",
      'an empty status' => "status:\n",
      'a numeric status' => "status: 1\n"
    }.each do |label, content|
      it "fails only that publication when publication-status.yaml is #{label}" do
        write('documents/T-SP-E.118-2018/publication-status.yaml', content)
        result = run_render(docs: ['T-SP-E.118-2018', 'T-SP-PP.RES.21-2011'], langs: ['E'])
        expect(reasons(result).keys).to eq(['T-SP-E.118-2018-E.adoc'])
        expect(manifest_json['publications'].map { |e| e['standard'] }).to eq(['PP.RES.21'])
      end
    end

    it 'keeps candidate for a status file with no status key' do
      write('documents/T-SP-E.118-2018/publication-status.yaml', "note: pending\n")
      run_render(docs: ['T-SP-E.118-2018'], langs: ['E'])
      expect(manifest_json['publications'].first['status']).to eq('candidate')
    end

    it 'deletes an earlier manifest and log when the run aborts (duplicate rows)' do
      FileUtils.mkdir_p(File.join(out_dir, 'pdf'))
      File.write(File.join(out_dir, 'pdf', 'manifest.json'), '{"publications":["stale"]}')
      write('documents/T-SP-E.118-2018/T-SP-E.118-2018-v2-E.adoc', File.read(File.join(@root, 'documents/T-SP-E.118-2018/T-SP-E.118-2018-E.adoc')))
      expect { run_render(docs: ['T-SP-E.118-2018']) }.to raise_error(ArgumentError, /duplicate/)
      expect(File.exist?(File.join(out_dir, 'pdf', 'manifest.json'))).to be(false)
    end

    it 'replaces an earlier run output with this run output' do
      FileUtils.mkdir_p(File.join(out_dir, 'pdf'))
      File.write(File.join(out_dir, 'pdf', 'old.pdf'), 'stale')
      File.write(File.join(out_dir, 'render-failures.log'), 'stale')
      run_render(docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
      expect(File.exist?(File.join(out_dir, 'pdf', 'old.pdf'))).to be(false)
      expect(File.read(File.join(out_dir, 'render-failures.log'))).to eq('')
    end

    it 'fails an entry whose renderer returns an empty PDF' do
      empty = lambda do |adoc|
        pdf = adoc.sub(/\.adoc\z/, '.pdf')
        File.binwrite(pdf, '')
        [pdf, nil]
      end
      result = run_with(empty, docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
      expect(reasons(result).values.first).to match(/empty or missing PDF/)
      expect(manifest_json['publications']).to eq([])
    end

    it 'fails an entry whose renderer returns [nil, nil] with a reason' do
      result = run_with(->(_adoc) { [nil, nil] }, docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
      expect(reasons(result).values.first).to match(/no PDF and no reason/)
    end

    describe 'the default renderer' do
      around do |example|
        Dir.mktmpdir do |bin|
          @bin = bin
          old = ENV.fetch('PATH')
          ENV['PATH'] = "#{bin}:#{old}"
          begin
            example.run
          ensure
            ENV['PATH'] = old
          end
        end
      end

      # with_unbundled_env restores the PATH bundler saw at boot, which would hide the stub.
      before { allow(Bundler).to receive(:with_unbundled_env) { |&block| block.call } }

      def stub_metanorma(body)
        path = File.join(@bin, 'metanorma')
        File.write(path, "#!/bin/sh\n#{body}\n")
        File.chmod(0o755, path)
      end

      it 'does not accept a stale PDF when metanorma exits 0 without writing one' do
        stub_metanorma('exit 0')
        adoc = File.join(@root, 'documents/T-SP-PP.RES.21-2011/T-SP-PP.RES.21-2011-E.adoc')
        File.binwrite(adoc.sub('.adoc', '.pdf'), 'stale bytes')
        result = described_class.run(root: @root, out_dir: out_dir, docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
        expect(reasons(result).values.first).to eq('metanorma produced no PDF')
        expect(manifest_json['publications']).to eq([])
      end

      it 'gives metanorma the container env passed in RENDER_ORIG_*, not an empty unbundled env' do
        seen = File.join(@root, 'seen')
        stub_metanorma(%(echo "RUBYOPT=$RUBYOPT BG=$BUNDLE_GEMFILE" > #{seen}; printf pdf > "${6%.adoc}.pdf"))
        env = { 'RENDER_ORIG_RUBYOPT' => '-rbundler/setup', 'RENDER_ORIG_BUNDLE_GEMFILE' => '/setup/Gemfile' }
        old = env.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
        env.each { |k, v| ENV[k] = v }
        begin
          described_class.run(root: @root, out_dir: out_dir, docs: ['T-SP-PP.RES.21-2011'], langs: ['E'])
        ensure
          old.each { |k, v| ENV[k] = v }
        end
        expect(File.read(seen).strip).to eq('RUBYOPT=-rbundler/setup BG=/setup/Gemfile')
      end

      it 'maps the RENDER_ORIG_* variables, empty meaning unset, absent meaning untouched' do
        expect(described_class.metanorma_env('RENDER_ORIG_RUBYOPT' => '-rx', 'RENDER_ORIG_BUNDLE_GEMFILE' => ''))
          .to eq('RUBYOPT' => '-rx', 'BUNDLE_GEMFILE' => nil)
        expect(described_class.metanorma_env({})).to eq({})
      end
    end

    describe 'site rules' do
      it 'fails an entry with as_of_issue 0' do
        write('datasets/0-zero/data.yaml', "- a: 1\n")
        write('datasets/0-zero/metadata.yaml', "title:\n  en: Zero\n")
        doc('T-SP-Z.1-2020', 'E', '0-zero')
        result = run_render(docs: ['T-SP-Z.1-2020'])
        expect(result.failures.map(&:reason).join).to match(/invalid as_of_issue/)
        expect(manifest_json['publications']).to eq([])
      end

      it 'fails an entry with as_of_issue above 2^53-1' do
        write('datasets/99999999999999999999-big/data.yaml', "- a: 1\n")
        write('datasets/99999999999999999999-big/metadata.yaml', "title:\n  en: Big\n")
        doc('T-SP-Z.2-2020', 'E', '99999999999999999999-big')
        result = run_render(docs: ['T-SP-Z.2-2020'])
        expect(result.failures.map(&:reason).join).to match(/invalid as_of_issue/)
        expect(manifest_json['publications']).to eq([])
      end

      it 'fails an entry whose path the site would reject' do
        doc('T-SP-Q?x#y%z-2020', 'E', '1161-E.118')
        result = run_render(docs: ['T-SP-Q?x#y%z-2020'])
        expect(result.failures.map(&:reason).join).to match(/unsafe path/)
        expect(manifest_json['publications']).to eq([])
      end

      it 'accepts what the site accepts and rejects what it rejects (safe_pdf_path?)' do
        ok = %w[pdf/E.118-2018/E.118-2018-E.pdf a/b.PDF]
        bad = ['', '/a.pdf', 'a//b.pdf', 'a/../b.pdf', './a.pdf', 'a\\b.pdf', 'a?b.pdf', 'a#b.pdf', 'a%b.pdf',
               'https://x/a.pdf', "a\nb.pdf", 'a/b.txt']
        expect(ok.map { |p| described_class.safe_pdf_path?(p) }).to all(be(true))
        expect(bad.map { |p| described_class.safe_pdf_path?(p) }).to all(be(false))
      end

      it 'checks every field the site checks' do
        good = Ituob::Models::PublicationManifestEntry.new(
          standard: 'E.118', title: 'T', edition_year: 2018, language: 'en', as_of_issue: 1,
          sha256: 'a' * 64, status: 'candidate', register_slugs: ['e118-iin'], path: 'pdf/E.118-2018/x.pdf'
        )
        expect(described_class.invalid_reason(good)).to be_nil
        {
          standard: ' ', title: '', edition_year: 0, language: 'english', as_of_issue: 2**53, sha256: 'xyz',
          register_slugs: ['Bad Slug'], path: '../x.pdf'
        }.each do |field, value|
          copy = good.dup
          copy.public_send(:"#{field}=", value)
          expect(described_class.invalid_reason(copy)).not_to be_nil, "#{field}=#{value.inspect} should be rejected"
        end
      end
    end
  end
end
