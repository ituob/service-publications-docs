# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Provider, 'site snapshot parity' do
  let(:register) { Ituob::Catalogs::Registers.find_by_slug('e212-mnc') }
  let(:edition) { described_class.new.edition(register: 'e212-mnc', as_of: 1170) }
  let(:snapshot) do
    # Use the same replay factory as scripts/generate_register_snapshots.rb.
    replay = Ituob::Verifiers::RegisterStateIntegrityVerifier.build_replay(register)
    replay.at_issue(1170).to_snapshot(slug: 'e212-mnc')
  end

  it 'preserves every E212_MNC item key in the snapshot order at issue 1170' do
    expected_keys = snapshot.fetch('active_entries').map { |row| row.fetch('mcc_mnc_codes') }

    expect(expected_keys.size).to be > 1
    expect(edition.items.map(&:mcc_mnc_codes)).to eq(expected_keys)
  end

  it 'renders the same as-of provenance line as the site snapshot' do
    # Wording shared by the site and docs/proof/e212-1170.adoc.
    template = Liquid::Template.parse(
      'State as of OB No. {{ edition.provenance.as_of_issue }} · {{ edition.items.size }} active entries'
    )
    expected_line = "State as of OB No. #{snapshot.fetch('at_ob_issue')} · " \
                    "#{snapshot.fetch('entry_count')} active entries"

    expect(snapshot.fetch('at_ob_issue')).to eq(1170)
    expect(edition.provenance.register_id).to eq('E212_MNC')
    expect(template.render!('edition' => edition)).to eq(expected_line)
  end
end
