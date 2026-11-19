# frozen_string_literal: true

require 'spec_helper'
require 'ituob/catalogs'
require 'ituob/registers'
require 'ituob/verifiers'

RSpec.describe 'Stored Q.708 ISPC deletion in OB 1335' do
  let(:deleted_codes) { %w[2-080-2 2-080-3 2-081-6] }

  # Official OB 1335, printed page 17: Spain ADD, followed by Sweden DEL.
  it 'stores the Sweden deletion separately from the Spain addition' do
    patches = Dir.glob(File.join(OB_ISSUES_ROOT, '1335/q708-ispc/*.yaml')).sort.map do |path|
      Ituob::Support::Yaml.safe_load_file(path)
    end

    expect(patches.map { |patch| patch.fetch('type') }).to eq(%w[ADD DEL])
    addition, deletion = patches.map { |patch| patch.fetch('data').fetch('entries') }
    expect(addition.map { |entry| entry.fetch('ipsc') }).to eq(['2-027-4'])
    expect(addition.map { |entry| entry.dig('country', 'en') }).to eq(['Spain'])
    expect(deletion.map { |entry| entry.fetch('ipsc') }).to eq(deleted_codes)
    expect(deletion.map { |entry| entry.dig('country', 'en') }.uniq).to eq(['Sweden'])
  end

  it 'removes the Swedish codes from the register while retaining the Spanish addition' do
    register = Ituob::Catalogs::Registers.find('Q708_ISPC')
    replay = Ituob::Verifiers::RegisterStateIntegrityVerifier.build_replay(register)
    state = replay.at_issue(1335)

    expect(state.active_keys & deleted_codes).to be_empty
    expect(state.deleted_keys & deleted_codes).to match_array(deleted_codes)
    expect(state.active_entries.fetch('2-027-4')).to include('country' => { 'en' => 'Spain' })
  end
end
