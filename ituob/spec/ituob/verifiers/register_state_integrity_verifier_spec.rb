# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'ituob/catalogs'
require 'ituob/registers'
require 'ituob/verifiers'

RSpec.describe Ituob::Verifiers::RegisterStateIntegrityVerifier do
  let(:tmpdir) { Dir.mktmpdir('register-state-integrity-spec') }
  after { FileUtils.rm_rf(tmpdir) }

  let(:register_id) { 'TEST' }
  let(:key_field) { 'code' }
  let(:register) do
    Ituob::Catalogs::Registers::Entry.new(
      register_id: register_id, slug: 'test', key_field: key_field,
      seed_issue: 1000, seed_path: 'datasets/1000-Test',
      fallback_key_fields: ['legacy_code'],
    )
  end
  let(:catalog_entries) { [register] }
  let(:catalog) do
    entries = catalog_entries
    Object.new.tap do |object|
      object.define_singleton_method(:each_entry) { |&block| entries.each(&block) }
    end
  end
  let(:verifier) { described_class.new(registers_catalog: catalog, root: tmpdir) }
  let(:entries) { { 'ABC' => { 'code' => 'ABC' } } }
  let(:ob_issue) { 1000 }
  let(:lapsed_keys) { [] }
  let(:state) do
    Ituob::Registers::State.new(
      register_id: register_id, at_ob_issue: ob_issue, entries: entries,
      lapsed_keys: lapsed_keys, deleted_keys: [], history: [],
    )
  end
  let(:result) { verifier.verify_state(state, register: register) }

  describe '#verify_state' do
    it 'passes a valid scalar key and reports state counts' do
      expect(result).to be_a(Ituob::Verifiers::Base::Result)
      expect(result).to be_passed
      expect(result.warnings).to be_empty
      expect(result.details).to eq([
                                     { register_id: 'TEST', slug: 'test', ob_issue: 1000,
                                       entry_count: 1, invalid_entry_count: 0 },
                                   ])
    end

    context 'with nil and whitespace-only derived keys' do
      let(:entries) do
        { 'missing' => {}, 'nil-value' => { 'code' => nil },
          'spaces' => { 'code' => " \t\n" }, 'nbsp' => { 'code' => " \u00a0 " } }
      end

      it 'flags every row under rule (a) and counts each invalid row once' do
        %w[missing nil-value spaces nbsp].each do |stored_key|
          expect(result.errors).to include(a_string_including('TEST', '1000', stored_key, '(a)'))
        end
        expect(result.details.first[:invalid_entry_count]).to eq(4)
      end
    end

    context 'with an invalid lapsed row' do
      let(:entries) { { 'ABC' => { 'code' => 'ABC' }, 'old' => { 'code' => nil } } }
      let(:lapsed_keys) { ['old'] }

      it 'checks and counts only active entries' do
        expect(result).to be_passed
        expect(result.details.first).to include(entry_count: 1, invalid_entry_count: 0)
      end
    end

    context 'with NBSP in a stored or derived key' do
      let(:entries) do
        { "A\u00a0B" => { 'code' => "A\u00a0B" },
          "C\u00a0D" => { 'code' => 'CD' },
          'EF' => { 'code' => "E\u00a0F" } }
      end

      it 'reports rule (b) for derived keys and rule (d) for a differing stored key' do
        expect(result.errors.count { |error| error.include?('(b)') }).to eq(2)
        expect(result.errors).to include(a_string_including('CD', '(d)'))
        expect(result.details.first[:invalid_entry_count]).to eq(3)
      end
    end

    context 'with a mismatched stored key in current' do
      let(:ob_issue) { nil }
      let(:entries) { { 'OLD' => { 'code' => 'NEW' } } }

      it 'identifies the register, current state, stored and recomputed keys' do
        expect(result.errors).to include(a_string_including('TEST', 'current', 'OLD', 'NEW', '(d)'))
        expect(result.details.first).to include(ob_issue: 'current', invalid_entry_count: 1)
      end
    end

    context 'with duplicate derived keys under distinct stored keys' do
      let(:entries) { { 'ABC' => { 'code' => 'ABC' }, 'OTHER' => { 'code' => 'ABC' } } }

      it 'flags both rows, including the row whose stored key matches' do
        expect(result.errors).to include(a_string_including('ABC', '(d)', 'duplicate'))
        expect(result.errors).to include(a_string_including('OTHER', '(d)', 'duplicate'))
        expect(result.details.first[:invalid_entry_count]).to eq(2)
      end
    end

    context 'with composite keys' do
      let(:key_field) { %w[country_or_area network_code office_code] }
      let(:entries) do
        { 'Chili | XX | SANT' => {
          'country_or_area' => { 'en' => 'Chile', 'fr' => 'Chili' }, 'network_code' => 'XX', 'office_code' => 'SANT',
        } }
      end

      it 'passes complete composite keys using replay language selection' do
        expect(result).to be_passed
        expect(result.details.first[:invalid_entry_count]).to eq(0)
      end

      context 'with a blank component' do
        let(:entries) do
          { 'Chile |  | SANT' => {
            'country_or_area' => 'Chile', 'network_code' => " \t", 'office_code' => 'SANT',
          } }
        end

        it 'names the missing field under rule (c)' do
          expect(result.errors).to include(a_string_including('TEST', '1000', 'Chile |  | SANT', '(c)', 'network_code'))
        end
      end

      context 'for F32_TDI coast station offices' do
        let(:register_id) { 'F32_TDI' }
        let(:entries) do
          { 'Chile |  | UICX' => {
            'country_or_area' => 'Chile', 'office_code' => 'UICX',
          } }
        end

        it 'allows an absent network_code for a four-letter office' do
          expect(result).to be_passed
        end

        context 'with a Chile heading and two short offices' do
          let(:entries) do
            { 'Chile | XX- - | ' => { 'country_or_area' => 'Chile', 'network_code' => 'XX- -' },
              'Chile |  | --AB' => { 'country_or_area' => 'Chile', 'office_code' => '--AB' },
              'legacy-office' => { 'country_or_area' => 'Chile', 'office_code' => '--AB' } }
          end

          it 'rejects the heading and missing networks on hyphenated offices' do
            expect(result.errors).to include(a_string_including('Chile | XX- - | ', '(c)', 'office_code'))
            expect(result.errors).to include(a_string_including('Chile |  | --AB', '(c)', 'network_code'))
            expect(result.errors).to include(a_string_including('legacy-office', '(c)', 'network_code'))
            expect(result.errors).to include(a_string_including('Chile |  | --AB', '(d)', 'duplicate'))
            expect(result.errors).to include(a_string_including('legacy-office', '(d)', 'duplicate'))
            expect(result.details.first[:invalid_entry_count]).to eq(3)
          end
        end

        context 'with a non-ASCII four-letter office' do
          let(:entries) { { 'Chile |  | UICÉ' => { 'country_or_area' => 'Chile', 'office_code' => 'UICÉ' } } }

          it 'keeps the network component mandatory' do
            expect(result.errors).to include(a_string_including('(c)', 'network_code'))
          end
        end

        context 'with a missing country' do
          let(:entries) { { ' |  | UICX' => { 'office_code' => 'UICX' } } }

          it 'keeps other components mandatory' do
            expect(result.errors).to include(a_string_including('(c)', 'country_or_area'))
          end
        end
      end

      context 'for another register with the same office shape' do
        let(:entries) { { 'Chile |  | UICX' => { 'country_or_area' => 'Chile', 'office_code' => 'UICX' } } }

        it 'keeps the network component mandatory' do
          expect(result.errors).to include(a_string_including('(c)', 'network_code'))
        end
      end
    end
  end

  describe '.build_replay' do
    it 'shares the catalog key configuration and resolves the seed path under root' do
      replay = described_class.build_replay(register, root: tmpdir)

      expect(replay).to be_a(Ituob::Registers::Replay)
      expect(replay.register_id).to eq('TEST')
      expect(replay.key_field).to eq('code')
      expect(replay.fallback_key_fields).to eq(['legacy_code'])
      expect(replay.source).to be_a(Ituob::Registers::DirectoryChangeSource)
      expect(replay.source.seed_path).to eq(File.join(tmpdir, 'datasets/1000-Test'))
      expect(replay.source.seed_issue).to eq(1000)
    end
  end

  describe '#verify' do
    let(:seed_directory) { File.join(tmpdir, register.seed_path) }
    before do
      FileUtils.mkdir_p(File.join(seed_directory, 'changes'))
      File.write(File.join(seed_directory, 'data.yaml'), [{ 'code' => 'ABC' }].to_yaml)
    end

    it 'checks seed and current states from a root independent of the working directory' do
      result = Dir.chdir(File.join(seed_directory, 'changes')) { verifier.verify }

      expect(result).to be_passed
      expect(result.details).to contain_exactly(
        { register_id: 'TEST', slug: 'test', ob_issue: 1000, entry_count: 1, invalid_entry_count: 0 },
        { register_id: 'TEST', slug: 'test', ob_issue: 'current', entry_count: 1, invalid_entry_count: 0 },
      )
    end

    context 'with an invalid amendment removed by a later amendment' do
      before do
        File.write(File.join(seed_directory, 'changes', '1001-ADD.yaml'), {
          'type' => 'ADD', 'identifier' => { 'code' => ' ' },
          'ob_issue_no' => 1001, 'data' => { 'code' => ' ' },
        }.to_yaml)
        File.write(File.join(seed_directory, 'changes', '1002-DEL.yaml'), {
          'type' => 'DEL', 'identifier' => { 'code' => ' ' }, 'ob_issue_no' => 1002,
        }.to_yaml)
      end

      it 'reports the invalid historical state even when current is clean' do
        result = verifier.verify

        expect(result.errors).to include(a_string_including('TEST', '1001', '(a)'))
        expect(result.details).to include(
          { register_id: 'TEST', slug: 'test', ob_issue: 1001, entry_count: 2, invalid_entry_count: 1 },
          { register_id: 'TEST', slug: 'test', ob_issue: 1002, entry_count: 1, invalid_entry_count: 0 },
          { register_id: 'TEST', slug: 'test', ob_issue: 'current', entry_count: 1, invalid_entry_count: 0 },
        )
      end
    end

    context 'with external and seedless registers' do
      let(:catalog_entries) do
        [register,
         Ituob::Catalogs::Registers::Entry.new(register_id: 'EXT', slug: 'external', external: true,
                                               seed_issue: 1000, seed_path: 'missing', key_field: 'code'),
         Ituob::Catalogs::Registers::Entry.new(register_id: 'NO_SEED', slug: 'seedless', key_field: 'code')]
      end

      it 'reports only replayable registers' do
        result = verifier.verify

        expect(result).to be_passed
        expect(result.details.map { |detail| detail[:register_id] }).to eq(%w[TEST TEST])
      end
    end
  end
end
