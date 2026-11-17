# frozen_string_literal: true

require 'spec_helper'
require 'ituob/verifiers'

RSpec.describe 'Post-amendment annex seeds' do
  %w[E118_IIN E164_CC E164_NOTE_PQ E212_MNC Q708_ISPC].each do |register_id|
    it "does not replay #{register_id}'s seed-issue patches" do
      entry = Ituob::Catalogs::Registers.find(register_id)
      replay = Ituob::Verifiers::RegisterStateIntegrityVerifier.build_replay(entry)
      seed = replay.source.each_sorted.first
      state = replay.at_seed

      expect(state.history.map(&:type)).to eq(['SEED'])
      expect(state.errors).to be_empty
      seed_source = Ituob::Registers::InlineChangeSource.new(register_id: register_id, changes: [seed])
      seed_state = Ituob::Registers::Replay.new(
        register_id: register_id, key_field: entry.key_field,
        fallback_key_fields: entry.fallback_key_fields, source: seed_source
      ).current
      expect(state.entries).to eq(seed_state.entries)
      expect(state.lapsed_keys).to be_empty
      expect(state.deleted_keys).to be_empty
    end
  end
end
