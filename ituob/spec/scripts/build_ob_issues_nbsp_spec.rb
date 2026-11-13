# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'

RSpec.describe 'scripts/build_ob_issues.rb NBSP policy' do
  let(:script) { File.expand_path('../../../scripts/build_ob_issues.rb', __dir__) }
  let(:writer) do
    methods = Module.new
    methods.extend(methods)
    methods.module_eval(File.read(script), script)
    methods
  end
  let(:root) { Dir.mktmpdir('build-ob-issues-nbsp') }
  let(:path) { File.join(root, '1000', dataset_slug, '001-ADD.yaml') }
  let(:printed_text) { "Printed\u00a0wording" }
  let(:data) do
    {
      'entries' => rows,
      'description' => printed_text,
      'notes' => [printed_text]
    }
  end
  let(:patch) do
    change = writer.write_change_object(
      issue_id: 1000, dataset_slug: dataset_slug, seq: '001',
      date_active: '2020-01-01', identifier: { 'code' => "P\u00a01" },
      data: data, description: printed_text
    )
    writer.write_yaml(path, change)
    YAML.safe_load_file(path)
  end

  after { FileUtils.remove_entry(root) }

  context 'with a scalar key' do
    let(:dataset_slug) { 'e212-mnc' }
    let(:rows) do
      [
        { 'mcc_mnc_codes' => "901\u00a065", 'network' => { 'en' => printed_text } },
        { 'mcc_mnc_codes' => '230 01', 'network' => { 'en' => printed_text } }
      ]
    end

    it 'writes clean keys and retains text values exactly as printed' do
      expect(patch['identifier']).to eq('code' => 'P 1')
      expected_rows = [
        { 'mcc_mnc_codes' => '901 65', 'network' => { 'en' => printed_text } },
        { 'mcc_mnc_codes' => '230 01', 'network' => { 'en' => printed_text } }
      ]
      expect(patch['data']['entries']).to eq(expected_rows)
      expect(patch['data']['description']).to eq(printed_text)
      expect(patch['data']['notes']).to eq([printed_text])
      expect(patch['description']).to eq(printed_text)
      keys = patch['data']['entries'].map do |row|
        Ituob::Registers::Strategies::Base.entry_key(row, 'mcc_mnc_codes')
      end
      expect(keys).to eq(['901 65', '230 01'])
    end
  end

  context 'with composite and multilingual key fields' do
    let(:dataset_slug) { 'f32-tdi' }
    let(:rows) do
      [{ 'country_or_area' => { 'en' => "NEW\u00a0ZEALAND", 'fr' => "NOUVELLE\u00a0ZÉLANDE" },
         'network_code' => "NZ\u00a0", 'office_code' => "\u00a0AB",
         'office_name' => printed_text }]
    end

    it 'cleans every component and language without changing non-key text' do
      row = patch['data']['entries'].first
      expect(row).to eq(
        'country_or_area' => { 'en' => 'NEW ZEALAND', 'fr' => 'NOUVELLE ZÉLANDE' },
        'network_code' => 'NZ ', 'office_code' => ' AB', 'office_name' => printed_text
      )
      key = Ituob::Registers::Strategies::Base.entry_key(row, %w[country_or_area network_code office_code])
      expect(key).to eq('NOUVELLE ZÉLANDE | NZ  |  AB')
    end
  end

  context 'with fallback and routed key fields' do
    let(:dataset_slug) { 'e164-cc' }
    let(:rows) do
      [{ 'country_code' => nil, 'cc_ic' => "+882\u00a013", 'notes' => printed_text },
       { 'country_code' => "+44\u00a0", 'cc_ic' => "+883\u00a05140", 'notes' => printed_text }]
    end

    it 'cleans fallback fields even when the primary key is present' do
      expected_rows = [
        { 'country_code' => nil, 'cc_ic' => '+882 13', 'notes' => printed_text },
        { 'country_code' => '+44 ', 'cc_ic' => '+883 5140', 'notes' => printed_text }
      ]
      expect(patch['data']['entries']).to eq(expected_rows)
      keys = patch['data']['entries'].map do |row|
        Ituob::Registers::Strategies::Base.entry_key(row, 'country_code', ['cc_ic'])
      end
      expect(keys).to eq(['+882 13', '+44 '])
    end
  end

  context 'when building a parsed amendment' do
    let(:dataset_slug) { 'e164-cc' }
    let(:source) { File.join(root, 'source') }
    let(:document) do
      paragraph = ->(text) { { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] } }
      table_rows = [%w[Applicant Network Code Status],
                    [printed_text, printed_text, "+882\u00a013", 'Assigned']]
      table = {
        'type' => 'table',
        'content' => table_rows.map do |cells|
          { 'type' => 'table_row', 'content' => cells.map do |text|
            { 'type' => 'table_cell', 'content' => [paragraph.call(text)] }
          end }
        end
      }
      { 'type' => 'doc', 'content' => [table, paragraph.call("ISPC:\u00a0#{printed_text}")] }
    end

    it 'writes clean entry keys while preserving parsed text and extracted notes' do
      message = { 'type' => 'amendment', 'target' => { 'publication' => 'E164_CC' },
                  'contents' => { 'en' => document } }
      writer.write_yaml(File.join(source, 'amendments.yaml'), 'messages' => [message])
      stats = Hash.new(0)
      stats[:by_amendment_target] = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      writer.process_amendments(1000, source, File.join(root, '1000'), stats)

      written = YAML.safe_load_file(path)
      expect(written['data']['entries'].first).to include(
        'cc_ic' => '+882 13', 'applicant' => printed_text, 'network' => printed_text
      )
      expect(written['data']['notes']).to eq(["ISPC:\u00a0#{printed_text}"])
    end
  end
end
