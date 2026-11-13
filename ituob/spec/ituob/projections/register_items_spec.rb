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
