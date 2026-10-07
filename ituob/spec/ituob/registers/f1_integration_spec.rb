# frozen_string_literal: true

require 'spec_helper'
require 'ituob/registers'
require 'ituob/catalogs'

RSpec.describe 'F1 register integration', :integration do
  let(:register) { Ituob::Catalogs::Registers.find('F1') }
  let(:source) do
    Ituob::Registers::DirectoryChangeSource.new(
      register_id: register.register_id,
      seed_path: register.seed_path,
      seed_issue: register.seed_issue,
      key_field: register.key_field,
    )
  end
  let(:replay) do
    Ituob::Registers::Replay.new(
      register_id: register.register_id,
      key_field: register.key_field,
      source: source,
    )
  end

  it 'has a catalogued register' do
    expect(register).not_to be_nil
    expect(register.title_en).to include('Five-letter Code Groups')
    expect(register.recommendation).to eq('F.1')
    expect(register.key_field).to eq('code')
  end

  it 'has a seed directory on disk' do
    expect(File.exist?(File.join(register.seed_path, 'data.yaml'))).to be true
  end

  it 'replays the seed to 170 active entries' do
    state = replay.at_seed
    expect(state.entry_count).to eq(170)
  end

  it 'has specific known entries' do
    state = replay.at_seed
    expect(state.entry_for('APHAD')['field']).to eq('accounts')
    expect(state.entry_for('APHAD')['message']['en']).to eq('We are debiting you.')
    expect(state.entry_for('TUHRU')['field']).to eq('miscellaneous')
    expect(state.entry_for('TUHRU')['message']['en']).to eq('Say if in agreement.')
  end

  it 'has no lapsed or deleted entries at seed' do
    state = replay.at_seed
    expect(state.lapsed_keys).to be_empty
    expect(state.deleted_keys).to be_empty
  end

  it 'has no replay errors' do
    state = replay.at_seed
    expect(state.error_count).to eq(0)
  end

  it 'produces a frozen State' do
    expect(replay.at_seed).to be_frozen
  end

  it 'produces the same state via build_all_states' do
    all_states = replay.build_all_states
    seed_state = all_states[register.seed_issue]
    expect(seed_state).not_to be_nil
    expect(seed_state.entry_count).to eq(170)
  end
end
