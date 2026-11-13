# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Projections::RegisterItems, 'E212_MNC hydration' do
  subject(:projection) { described_class.new(register: register) }

  let(:register) { Ituob::Catalogs::Registers.find('E212_MNC') }
  let(:replay) do
    source = Ituob::Registers::DirectoryChangeSource.new(
      **register.to_h.slice(:register_id, :seed_issue, :key_field),
      seed_path: File.expand_path("../../../../#{register.seed_path}", __dir__)
    )
    Ituob::Registers::Replay.new(
      **register.to_h.slice(:register_id, :key_field, :fallback_key_fields),
      source: source
    )
  end

  it 'hydrates active entries at issue 1170 in replay key order' do
    state = replay.at_issue(1170)
    items = projection.at_issue(1170)

    expect(state.active_entries).not_to be_empty
    expect(items).to all(be_a(Ituob::Models::E212MNCEntry))
    expect(items.size).to eq(state.active_entries.size)
    expect(items.map(&:mcc_mnc_codes)).to eq(state.active_entries.keys)
    expect(items.map(&:networks)).to eq(state.active_entries.values.map { |row| row['networks'] })
    expect(items.first.country_or_area.en).to eq(state.active_entries.values.first.dig('country_or_area', 'en'))
  end
end

RSpec.shared_context 'replayed projection rows' do
  let(:register) { Ituob::Catalogs::Registers.find(register_id) }
  let(:items) { described_class.new(register: register).at_issue(1170) }
  let(:rows) do
    source = Ituob::Registers::DirectoryChangeSource.new(
      **register.to_h.slice(:register_id, :seed_issue, :key_field),
      seed_path: File.expand_path("../../../../#{register.seed_path}", __dir__)
    )
    Ituob::Registers::Replay.new(
      **register.to_h.slice(:register_id, :key_field, :fallback_key_fields),
      source: source
    ).at_issue(1170).active_entries.values
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'E164_CC register fields' do
  include_context 'replayed projection rows'
  let(:register_id) { 'E164_CC' }

  it 'preserves country codes and multilingual labels alongside annex fields' do
    expect(items.size).to eq(rows.size)
    expect(items).to all(be_a(Ituob::Models::E164CCEntry))
    expect(items.first.to_hash).to include('country_code' => '0')
    expect(items.first.to_hash.fetch('country_area_or_service')).to include('en' => 'Reserved')
    expect(items.map { |item| item.to_hash['country_code'] }).to eq(rows.map { |row| row['country_code'] })
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'E164_CC list notes' do
  include_context 'replayed projection rows'
  let(:register_id) { 'E164_CC' }

  it 'retains each notes collection on the corresponding replayed row' do
    indices = rows.each_index.select { |index| rows.fetch(index).key?('notes') }
    expect(indices.size).to eq(11)
    indices.each do |index|
      expected = rows.fetch(index).fetch('notes')
      expect(items.fetch(index).notes).to eq(expected)
      expect(items.fetch(index).to_hash).to include('notes' => expected)
    end
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'T35_NA boolean values' do
  include_context 'replayed projection rows'
  let(:register_id) { 'T35_NA' }

  it 'retains true and false as booleans in every row and serialized entry' do
    expected = rows.map do |row|
      value = row.fetch('manufactures_htv')
      value == 'YES' ? true : value
    end
    expect(expected.count(false)).to eq(13)
    expect(expected.count(true)).to be_positive
    expect(items.map(&:manufactures_htv)).to eq(expected)
    expect(items.map { |item| item.to_hash.fetch('manufactures_htv') }).to eq(expected)
    expect(items.reject(&:manufactures_htv).size).to eq(13)
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'T35_NA authority fields' do
  include_context 'replayed projection rows'
  let(:register_id) { 'T35_NA' }

  it 'hydrates authority terminal type collections without losing their content' do
    expect(items.size).to eq(rows.size)
    expect(items).to all(be_a(Ituob::Models::T35NAEntry))
    expected = rows.first.fetch('assignment_authority').first
    authority = items.first.assignment_authority.first
    expect(authority).to be_a(Ituob::Models::T35AssignmentAuthority)
    expect(authority.terminal_type).to eq(expected.fetch('terminal_type'))
    expect(authority.to_hash).to include('last_updated' => expected.fetch('last_updated'))
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'F32_TDI multilingual notes' do
  include_context 'replayed projection rows'
  let(:register_id) { 'F32_TDI' }

  it 'hydrates multilingual network notes as models rather than inspect strings' do
    index = rows.index { |row| row['network_roa_note'].is_a?(Hash) }
    expect(index).not_to be_nil
    expect(items.size).to eq(rows.size)
    note = items.fetch(index).network_roa_note
    expect(note).to be_a(Ituob::Models::MultilingualString)
    expect(note.to_hash).to include(rows.fetch(index).fetch('network_roa_note'))
  end
end

%w[F400_ADMD DP].each do |register_id|
  RSpec.describe Ituob::Projections::RegisterItems, "#{register_id} empty strings" do
    include_context 'replayed projection rows'
    let(:register_id) { register_id }

    it 'preserves explicitly empty fields during deserialization and serialization' do
      indices = rows.each_index.select { |index| rows.fetch(index).value?('') }
      expect(indices).not_to be_empty
      indices.each do |index|
        empty_fields = rows.fetch(index).select { |_, value| value == '' }
        item = items.fetch(index)
        empty_fields.each_key { |field| expect(item.public_send(field)).to eq('') }
        expect(item.to_hash).to include(empty_fields)
        expect(item.to_hash).to include(register.key_field => rows.fetch(index).fetch(register.key_field))
        absent = item.class.attributes.keys.map(&:to_s) - rows.fetch(index).keys - ['_class']
        expect(item.to_hash.keys & absent).to be_empty
      end
    end
  end
end

RSpec.describe Ituob::Projections::RegisterItems, 'issue and register boundaries' do
  subject(:projection) { described_class.new(register: register) }

  let(:register) { Ituob::Catalogs::Registers.find('E212_MNC') }

  it 'returns no items before the seed issue' do
    expect(projection.at_issue(register.seed_issue - 1)).to eq([])
  end

  context 'with a textual external register' do
    let(:register) { Ituob::Catalogs::Registers.find('NNP') }

    it 'raises the documented error when no compiled Entry class exists' do
      expect { projection.at_issue(1170) }.to raise_error(
        described_class::UnsupportedRegisterError,
        'Register NNP has no compiled Entry class'
      )
    end
  end
end
