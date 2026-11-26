# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'yaml'
require_relative '../../../scripts/probe_backfill_sources'

RSpec.describe Backfill::SourceProbe do
  let(:resp) { Backfill::SourceProbe::Response }
  let(:dir) { Dir.mktmpdir }
  let(:cache) { File.join(dir, 'cache.json') }
  let(:sleeps) { [] }
  let(:now) { Time.utc(2026, 11, 26, 12) }
  let(:entry) do
    { 'number' => 700, 'class' => 'unresolved', 'expected_year' => 1999, 'evidence' => ['no ob-issues directory'] }
  end
  let(:msw) { 'https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.700-1999-OAS-MSW-E.doc' }
  let(:ok) { resp.new(200, 'application/msword') }

  # responses: url => Response, or an Array of Responses served in order (last one repeats); default 404
  def stub_client(responses)
    calls = []
    stub = Object.new
    stub.define_singleton_method(:calls) { calls }
    %i[head get].each do |verb|
      stub.define_singleton_method(verb) do |url|
        calls << [verb, url]
        r = responses.fetch(url, Backfill::SourceProbe::Response.new(404, 'text/html'))
        r.is_a?(Array) ? (r.size > 1 ? r.shift : r.first) : r
      end
    end
    stub
  end

  def build_probe(client, **opts)
    described_class.new(client: client, cache_path: cache, delay: 1.5, backoff: 2.0, clock: -> { now },
                        sleeper: ->(s) { sleeps << s }, **opts)
  end

  after { FileUtils.rm_rf(dir) }

  it 'marks the number b on a 200 for the English MSW file, recording the url' do
    build_probe(stub_client(msw => ok)).probe(entry)
    expect(entry).to include('class' => 'b', 'source_url' => msw)
    row = entry['evidence'].find { |e| e.is_a?(Hash) && e['url'] == msw }
    expect(row).to include('status' => 200, 'content_type' => 'application/msword', 'checked_at' => now.iso8601)
    expect(entry['evidence']).to include('no ob-issues directory')
  end

  it 'does not accept a 200 text/html answer for a file url' do
    build_probe(stub_client(msw => resp.new(200, 'text/html'))).probe(entry)
    expect(entry['class']).to eq('unresolved')
  end

  it 'leaves the number unresolved when everything is 404, listing every tried url' do
    build_probe(stub_client({})).probe(entry)
    rows = entry['evidence'].grep(Hash)
    urls = rows.map { |e| e['url'] }
    expect(entry['class']).to eq('unresolved')
    expect(entry).not_to have_key('source_url')
    expect(urls.size).to eq(3 * (1 + (3 * 3)))
    expect(urls).to include('https://www.itu.int/pub/T-SP-OB.700-1999', 'https://www.itu.int/pub/T-SP-OB.700-1998',
                            'https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.700-2000-OAS-PDF-S.pdf')
    expect(rows.map { |e| e['status'] }.uniq).to eq([404])
  end

  it 'records F/S hits as candidates without changing the class' do
    fr = 'https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.700-1999-OAS-PDF-F.pdf'
    build_probe(stub_client(fr => resp.new(200, 'application/pdf'))).probe(entry)
    expect(entry['class']).to eq('unresolved')
    expect(entry['candidates']).to eq([fr])
  end

  it 'retries a 429 after a delay and then accepts the answer' do
    client = stub_client(msw => [resp.new(429, nil), ok])
    build_probe(client).probe(entry)
    expect(entry['class']).to eq('b')
    expect(sleeps).to include(2.0)
    expect(client.calls.count { |_, u| u == msw }).to eq(2)
  end

  it 'sleeps the configured delay between requests and falls back to GET only when HEAD is refused' do
    client = stub_client(msw => resp.new(405, nil))
    build_probe(client).probe(entry)
    expect(sleeps).to include(1.5)
    i = client.calls.index([:head, msw])
    expect(client.calls[i + 1]).to eq([:get, msw])
    expect(client.calls.first).to eq([:head, 'https://www.itu.int/pub/T-SP-OB.700-1999'])
  end

  it 'gives up after the retry limit, listing the url as tried without caching the answer' do
    probe = build_probe(stub_client(msw => resp.new(503, nil)), retries: 2)
    probe.probe(entry)
    probe.save_cache
    expect(entry['class']).to eq('unresolved')
    expect(entry['evidence'].grep(Hash).find { |e| e['url'] == msw }).to include('status' => 503)
    expect(JSON.parse(File.read(cache))).not_to have_key(msw)
  end

  it 'lists a url that stays 429 after every retry as tried' do
    build_probe(stub_client(msw => resp.new(429, nil)), retries: 1).probe(entry)
    rows = entry['evidence'].grep(Hash)
    expect(rows.size).to eq(3 * (1 + (3 * 3)))
    expect(rows.find { |e| e['url'] == msw }).to include('status' => 429)
  end

  it 'lists a url whose requests all raise as tried with a nil status' do
    client = Object.new
    failing = msw
    client.define_singleton_method(:head) do |u|
      raise IOError if u == failing

      Backfill::SourceProbe::Response.new(404, nil)
    end
    client.define_singleton_method(:get) { |_| raise IOError }
    build_probe(client, retries: 1).probe(entry)
    expect(entry['evidence'].grep(Hash).find { |e| e['url'] == msw }).to include('status' => nil)
  end

  it 'reads its cache on a rerun and makes no repeat requests' do
    first = build_probe(stub_client(msw => ok))
    first.probe(entry)
    first.save_cache
    again = { 'number' => 700, 'class' => 'unresolved', 'expected_year' => 1999 }
    second_client = stub_client({})
    build_probe(second_client).probe(again)
    expect(second_client.calls).to be_empty
    expect(again['source_url']).to eq(msw)
  end

  it 'runs end to end over an inventory file, keeping its header' do
    FileUtils.mkdir_p(File.join(dir, 'docs/backfill'))
    path = File.join(dir, ProbeBackfillSources::INVENTORY)
    File.write(path, "# Generated\n---\ninventory:\n- number: 700\n  class: unresolved\n  expected_year: 1999\n  evidence: []\n")
    ProbeBackfillSources.run(root: dir, client: stub_client(msw => ok), sleeper: ->(_) {}, clock: -> { now })
    out = File.read(path)
    expect(out).to start_with("# Generated\n---\n")
    expect(YAML.safe_load(out)['inventory'].first).to include('class' => 'b', 'source_url' => msw)
    expect(File).to exist(File.join(dir, ProbeBackfillSources::CACHE))
  end

  it 'moves an unparseable cache aside and starts empty' do
    File.write(cache, '{"a": {"sta')
    probe = build_probe(stub_client({}))
    expect(probe.requests).to eq(0)
    expect(File).to exist("#{cache}.corrupt")
    expect(File).not_to exist(cache)
  end

  it 'never leaves a truncated cache when the write is interrupted' do
    probe = build_probe(stub_client(msw => ok))
    probe.probe(entry)
    probe.save_cache
    good = File.read(cache)
    allow(File).to receive(:write).and_wrap_original do |orig, path, data, *rest|
      orig.call(path, data[0, 5], *rest)
      raise Interrupt
    end
    expect { probe.save_cache }.to raise_error(Interrupt)
    expect(File.read(cache)).to eq(good)
  end

  it 'stops early with NetworkDown when every request raises, keeping the cache' do
    client = Object.new
    %i[head get].each { |v| client.define_singleton_method(v) { |_| raise IOError, 'down' } }
    probe = build_probe(client)
    expect { probe.probe_all([{ 'number' => 5, 'class' => 'unresolved', 'expected_year' => 1970 }]) }
      .to raise_error(Backfill::SourceProbe::NetworkDown, /IOError/)
    expect(probe.requests).to be <= 5
    expect(File).to exist(cache)
  end

  it 'does not trip on isolated network errors between answers' do
    calls = 0
    client = Object.new
    client.define_singleton_method(:head) do |_|
      (calls += 1).odd? ? raise(IOError) : Backfill::SourceProbe::Response.new(404, 'text/html')
    end
    expect { build_probe(client).probe(entry) }.not_to raise_error
  end
end
