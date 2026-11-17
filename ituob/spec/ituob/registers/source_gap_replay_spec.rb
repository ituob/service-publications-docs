# frozen_string_literal: true

require 'spec_helper'
require 'ituob/verifiers'

RSpec.describe 'Printed withdrawals with the verified F.32 seed' do
  let(:entry) { Ituob::Catalogs::Registers.find('X121_DNIC') }
  let(:replay) { Ituob::Verifiers::RegisterStateIntegrityVerifier.build_replay(entry) }

  [[1013, 'MALAYSIA'], [1148, 'UKRAINE']].each do |issue, country|
    it "applies the #{country} withdrawal from the verified source seed" do
      f32 = Ituob::Verifiers::RegisterStateIntegrityVerifier.build_replay(
        Ituob::Catalogs::Registers.find('F32_TDI')
      )
      prior = f32.at_issue(issue - 1)
      following = f32.at_issue(issue)
      expect(prior.active_entries.values.any? { |row| row.dig('country_or_area', 'en') == country }).to be true
      expect(following.errors).to be_empty
      expect(following.active_entries.values.none? { |row| row.dig('country_or_area', 'en') == country }).to be true
      neighbor = prior.active_entries.find { |_key, row| row.dig('country_or_area', 'en') == 'AFGHANISTAN' }
      expect(neighbor).not_to be_nil
      expect(following.entry_for(neighbor.first)).to eq(neighbor.last)
    end
  end

  it 'reports the absent printed DNIC while applying all neighboring withdrawals' do
    before = replay.at_issue(1080)
    after = replay.at_issue(1081)
    expect(before.active_keys.include?('206 1')).to be false
    expect(after.active_keys.include?('206 1')).to be false
    expect(after.errors).to contain_exactly(a_string_including('206 1', 'OB 1081', 'not present'))
    %w[2 4 5 8 9].each do |suffix|
      key = "206 #{suffix}"
      expect(before.active_keys.include?(key)).to be true
      expect(after.active_keys.include?(key)).to be false
    end
    expect(before.active_keys.include?('208 0')).to eq(after.active_keys.include?('208 0'))
  end
end
