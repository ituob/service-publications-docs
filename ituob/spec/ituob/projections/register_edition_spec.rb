# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Provider, 'edition and actions projections' do
  subject(:provider) { described_class.new }

  let(:register) { Ituob::Catalogs::Registers.find('E212_MNC') }
  let(:items_projection) { Ituob::Projections::RegisterItems.new(register: register) }
  let(:state) { items_projection.state_at(1170) }
  let(:edition) { provider.edition(register: 'e212-mnc', as_of: 1170) }
  let(:actions) { provider.actions(register: 'e212-mnc', as_of: 1170) }

  it 'projects issue 1170 items and provenance from the replayed edition' do
    expect(edition).to be_a(Ituob::Models::RegisterEdition)
    expect(edition.items.map(&:to_hash)).to eq(items_projection.hydrate(state).map(&:to_hash))
    expect(edition.provenance.as_of_issue).to eq(1170)
    expect(edition.provenance.register_id).to eq('E212_MNC')
    expect(edition.provenance.seed_issue).to eq(register.seed_issue)
    expect(edition.provenance.last_change_issue).to eq(state.last_issue)
  end

  it 'projects cumulative replay history as compiled RegisterChange models in order' do
    expect(actions).to be_a(Ituob::Models::RegisterActions)
    expect(actions.provenance.to_hash).to eq(edition.provenance.to_hash)
    expect(actions.changes.map(&:class).uniq).to eq([Ituob::Models::RegisterChange])
    expect(actions.changes.size).to eq(state.history.size)
    actions.changes.zip(state.history).each do |projected, original|
      expect(projected.type.value).to eq(original.type)
      expect(projected.identifier.to_hash).to eq(original.identifier.to_hash)
      (original.class.attributes.keys - %i[type identifier]).each do |attribute|
        expect(projected.public_send(attribute)).to eq(original.public_send(attribute))
      end
    end
  end

  it 'filters the pinned issue while retaining cumulative earlier changes' do
    before = provider.actions(register: 'e212-mnc', as_of: register.seed_issue)
    expected = state.history.select { |change| change.ob_issue_no == 1170 }

    expect(expected).not_to be_empty
    expect(actions.changes.map(&:ob_issue_no)).to include(be < 1170)
    selected = actions.changes.select { |change| change.ob_issue_no == actions.provenance.as_of_issue }
    expect(selected.map(&:ob_issue_no)).to all(eq(1170))
    expect(selected.map { |change| [change.type.value, change.identifier.to_hash, change.data] })
      .to eq(expected.map { |change| [change.type, change.identifier.to_hash, change.data] })
    expect(before.changes.map(&:ob_issue_no)).to all(be <= register.seed_issue)
    expect(before.changes.size).to be < actions.changes.size
    expect(before.provenance.as_of_issue).to eq(register.seed_issue)
  end

  it 'round trips all changes and provenance through YAML' do
    restored = Ituob::Models::RegisterActions.from_yaml(actions.to_yaml)

    expect(restored.provenance.to_hash).to eq(actions.provenance.to_hash)
    expect(restored.changes.map(&:class).uniq).to eq([Ituob::Models::RegisterChange])
    expect(restored.changes.map(&:to_hash)).to eq(actions.changes.map(&:to_hash))
  end

  it 'keeps key history consistent with replay-touched changes for that key' do
    key, changes = state.key_history.find do |candidate, entries|
      entries.any? { |change| change.identifier.code == candidate }
    end
    history = provider.history(register: 'e212-mnc', key: key, as_of: 1170)
    keyed_changes = state.history.select { |change| changes.include?(change) }

    expect(key).not_to be_nil
    expect(history.entries.map(&:ob_issue_no)).to eq(changes.map(&:ob_issue_no))
    expect(history.entries.map(&:ob_issue_no)).to eq(keyed_changes.map(&:ob_issue_no))
  end

  it 'rejects unknown registers, issues and pre-seed issues for actions' do
    expect { provider.actions(register: 'nope', as_of: 1170) }
      .to raise_error(Ituob::Provider::UnknownRegisterError)
    expect { provider.actions(register: 'e212-mnc', as_of: 99_999) }
      .to raise_error(Ituob::Provider::UnknownIssueError, 'Unknown OB issue 99999')
    expect { provider.actions(register: 'e212-mnc', as_of: register.seed_issue - 1) }
      .to raise_error(Ituob::Provider::UnknownIssueError, /no edition before its seed issue/)
  end
end
