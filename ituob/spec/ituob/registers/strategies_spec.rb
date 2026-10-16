# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'

RSpec.describe Ituob::Registers::Strategies::Add do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'ADD', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      data: { 'field' => 'accounts', 'message' => { 'en' => 'x' } },
    )
  end

  it 'inserts a new entry with the key field set' do
    described_class.call(builder, change, 'code')
    expect(builder.entries['ABC']['code']).to eq('ABC')
    expect(builder.entries['ABC']['field']).to eq('accounts')
  end

  it 'clears the lapsed flag' do
    builder.mark_lapsed('ABC')
    described_class.call(builder, change, 'code')
    expect(builder.lapsed_keys).not_to include('ABC')
  end

  it 'raises when key already exists' do
    builder.set_entry('ABC', { 'code' => 'ABC' })
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end
end

RSpec.describe Ituob::Registers::Strategies::Sup do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'SUP', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      superseded_by: { 'identifier' => { 'code' => 'DEF' } },
    )
  end

  it 'removes the entry and records deletion' do
    builder.set_entry('ABC', { 'code' => 'ABC' })
    described_class.call(builder, change, 'code')
    expect(builder.entries).not_to have_key('ABC')
    expect(builder.deleted_keys).to include('ABC')
  end

  it 'records the supersession' do
    builder.set_entry('ABC', { 'code' => 'ABC' })
    described_class.call(builder, change, 'code')
    expect(builder.supersessions['ABC']).to eq('DEF')
  end

  it 'raises when key is absent' do
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end
end

RSpec.describe Ituob::Registers::Strategies::Rep do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'REP', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      data: { 'field' => 'addresses', 'message' => { 'en' => 'updated' } },
    )
  end

  it 'wholesale-replaces the entry' do
    builder.set_entry('ABC', { 'code' => 'ABC', 'field' => 'accounts', 'extra' => 'drop me' })
    described_class.call(builder, change, 'code')
    expect(builder.entries['ABC']).to eq({
      'code' => 'ABC',
      'field' => 'addresses',
      'message' => { 'en' => 'updated' },
    })
  end

  it 'raises when key is absent' do
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end
end

RSpec.describe Ituob::Registers::Strategies::Lir do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'LIR', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      reason: { 'en' => 'Deprecated' },
    )
  end

  it 'marks the key as lapsed' do
    builder.set_entry('ABC', { 'code' => 'ABC' })
    described_class.call(builder, change, 'code')
    expect(builder.lapsed_keys).to include('ABC')
    expect(builder.lapse_reasons['ABC']).to eq({ 'en' => 'Deprecated' })
    # The entry itself remains in entries for audit.
    expect(builder.entries).to have_key('ABC')
  end

  it 'raises when key is absent' do
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end
end

RSpec.describe Ituob::Registers::Strategies::Mod do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'MOD', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      data: { 'message' => { 'en' => 'updated' } },
    )
  end

  it 'merges fields by default' do
    builder.set_entry('ABC', { 'code' => 'ABC', 'field' => 'accounts' })
    described_class.call(builder, change, 'code')
    expect(builder.entries['ABC']['field']).to eq('accounts')
    expect(builder.entries['ABC']['message']).to eq({ 'en' => 'updated' })
  end

  it 'wholesale-replaces when merge_strategy=replace_full' do
    change_full = Ituob::Registers::Change.new(
      type: 'MOD', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      data: { 'message' => { 'en' => 'updated' } },
      merge_strategy: 'replace_full',
    )
    builder.set_entry('ABC', { 'code' => 'ABC', 'field' => 'accounts' })
    described_class.call(builder, change_full, 'code')
    expect(builder.entries['ABC']).to eq({ 'code' => 'ABC', 'message' => { 'en' => 'updated' } })
  end

  it 'raises when key is absent' do
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end

  it 'deep-merges nested hashes (preserves other language keys)' do
    builder.set_entry('ABC', {
      'code' => 'ABC',
      'message' => { 'en' => 'original', 'fr' => 'original_fr' },
    })
    partial = Ituob::Registers::Change.new(
      type: 'MOD', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
      data: { 'message' => { 'en' => 'updated_en' } },
    )
    described_class.call(builder, partial, 'code')
    expect(builder.entries['ABC']['message']).to eq({
      'en' => 'updated_en', 'fr' => 'original_fr',
    })
  end
end

RSpec.describe Ituob::Registers::Strategies::Del do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'DEL', register_id: 'F1',
      identifier: { 'code' => 'ABC' },
    )
  end

  it 'hard-deletes and clears lapsed' do
    builder.set_entry('ABC', { 'code' => 'ABC' })
    builder.mark_lapsed('ABC')
    described_class.call(builder, change, 'code')
    expect(builder.entries).not_to have_key('ABC')
    expect(builder.lapsed_keys).not_to include('ABC')
    expect(builder.deleted_keys).to include('ABC')
  end

  it 'raises when key is absent' do
    expect {
      described_class.call(builder, change, 'code')
    }.to raise_error(Ituob::Registers::Strategies::StrategyError)
  end
end

RSpec.describe Ituob::Registers::Strategies::Seed do
  let(:builder) { Ituob::Registers::StateBuilder.new('F1') }
  let(:change) do
    Ituob::Registers::Change.new(
      type: 'SEED', register_id: 'F1',
      identifier: { 'code' => '__seed__' },
      data: [
        { 'code' => 'ABC', 'field' => 'accounts' },
        { 'code' => 'DEF', 'field' => 'addresses' },
      ],
    )
  end

  it 'expands the batch into individual entries' do
    described_class.call(builder, change, 'code')
    expect(builder.entries.keys).to contain_exactly('ABC', 'DEF')
  end

  it 'skips rows with empty key' do
    bad_change = Ituob::Registers::Change.new(
      type: 'SEED', register_id: 'F1',
      identifier: { 'code' => '__seed__' },
      data: [{ 'code' => '', 'field' => 'x' }, { 'code' => 'ABC' }],
    )
    described_class.call(builder, bad_change, 'code')
    expect(builder.entries.keys).to eq(['ABC'])
  end
end

RSpec.describe Ituob::Registers::Strategies, 'destructive? declarations' do
  it 'Base defaults to false' do
    expect(Ituob::Registers::Strategies::Base.destructive?).to be(false)
  end

  it 'Add is non-destructive' do
    expect(Ituob::Registers::Strategies::Add.destructive?).to be(false)
  end

  it 'Sup is destructive' do
    expect(Ituob::Registers::Strategies::Sup.destructive?).to be(true)
  end

  it 'Rep is non-destructive' do
    expect(Ituob::Registers::Strategies::Rep.destructive?).to be(false)
  end

  it 'Lir is destructive' do
    expect(Ituob::Registers::Strategies::Lir.destructive?).to be(true)
  end

  it 'Mod is non-destructive' do
    expect(Ituob::Registers::Strategies::Mod.destructive?).to be(false)
  end

  it 'Del is destructive' do
    expect(Ituob::Registers::Strategies::Del.destructive?).to be(true)
  end

  it 'Seed is non-destructive' do
    expect(Ituob::Registers::Strategies::Seed.destructive?).to be(false)
  end

  it 'ActionType#destructive? delegates to the strategy' do
    expect(Ituob::Registers::ActionType.new('SUP')).to be_destructive
    expect(Ituob::Registers::ActionType.new('LIR')).to be_destructive
    expect(Ituob::Registers::ActionType.new('DEL')).to be_destructive
    expect(Ituob::Registers::ActionType.new('ADD')).not_to be_destructive
    expect(Ituob::Registers::ActionType.new('REP')).not_to be_destructive
    expect(Ituob::Registers::ActionType.new('MOD')).not_to be_destructive
    expect(Ituob::Registers::ActionType.new('SEED')).not_to be_destructive
  end
end
