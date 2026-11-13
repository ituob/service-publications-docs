# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Ituob::Provider do
  before(:context) { @shared_provider = described_class.new }

  let(:provider) { @shared_provider }
  let(:register) { Ituob::Catalogs::Registers.find('E212_MNC') }
  let(:items_projection) { Ituob::Projections::RegisterItems.new(register: register) }
  let(:state) { items_projection.state_at(1170) }
  let(:edition) { provider.edition(register: 'e212-mnc', as_of: 1170) }

  describe 'data root' do
    around do |example|
      Dir.mktmpdir do |root|
        %w[catalogs datasets].each { |d| File.symlink(File.join(Ituob::DataRoot::CHECKOUT, d), File.join(root, d)) }
        FileUtils.mkdir_p(File.join(root, 'ob-issues', '1170'))
        @root = root
        example.run
      ensure
        Ituob::DataRoot.configure(nil)
      end
    end

    it 'reads issues from the explicit root, not the checkout' do
      rooted = described_class.new(data_root: @root)
      expect(rooted.edition(register: 'e212-mnc', as_of: 1170).items.size).to eq(state.active_entries.size)
      expect { rooted.edition(register: 'e212-mnc', as_of: 1171) }
        .to raise_error(described_class::UnknownIssueError, /Unknown OB issue 1171/)
    end

    it 'fails at construction with a root error when the root is wrong' do
      expect { described_class.new(data_root: '/nonexistent/ituob') }
        .to raise_error(Ituob::DataRoot::MissingError, %r{/nonexistent/ituob.*ITUOB_DATA_ROOT})
    end
  end

  describe '#lutaml_data_queries' do
    it 'names only the supported queries and each is a public method' do
      expect(provider.lutaml_data_queries).to eq(%i[edition history])
      expect(provider.lutaml_data_queries).to all(satisfy { |q| provider.respond_to?(q) })
      expect(provider.public_methods(false)).to contain_exactly(:lutaml_data_queries, :edition, :history)
    end
  end

  describe '#edition' do
    it 'returns a lutaml RegisterEdition of concrete compiled entries in replay order' do
      expect(edition).to be_a(Ituob::Models::RegisterEdition)
      expect(edition.items).to all(be_a(Ituob::Models::E212MNCEntry))
      expect(edition.items.map(&:mcc_mnc_codes)).to eq(state.active_entries.keys)
      expect(edition.items.size).to eq(state.active_entries.size)
    end

    it 'maps the slug and the catalog id to the same register' do
      by_id = provider.edition(register: 'E212_MNC', as_of: 1170)

      expect(by_id.provenance.register_id).to eq('E212_MNC')
      expect(by_id.items.map(&:mcc_mnc_codes)).to eq(edition.items.map(&:mcc_mnc_codes))
    end

    it 'records provenance for the requested issue' do
      expect(edition.provenance.register_id).to eq('E212_MNC')
      expect(edition.provenance.as_of_issue).to eq(1170)
      expect(edition.provenance.seed_issue).to eq(register.seed_issue)
      expect(edition.provenance.last_change_issue).to eq(state.last_issue)
    end

    it 'keeps lapsed and deleted membership apart from active items' do
      expect(edition.lapsed_keys).to eq(state.lapsed_keys.to_a.sort)
      expect(edition.deleted_keys).to eq(state.deleted_keys.to_a.sort)
      expect(edition.items.map(&:mcc_mnc_codes) & (edition.lapsed_keys + edition.deleted_keys)).to be_empty
    end

    it 'carries the touched-key history, not printed identifiers' do
      expected = state.key_history.flat_map { |key, changes| changes.map { |c| [key, c.type, c.ob_issue_no] } }

      expect(expected).not_to be_empty
      expect(edition.key_history.map { |e| [e.key, e.type.value, e.ob_issue_no] }).to eq(expected)
    end

    it 'restores through serialization with the same concrete types' do
      restored = Ituob::Models::RegisterEdition.from_yaml(edition.to_yaml)

      expect(restored.items.map(&:class).uniq).to eq([Ituob::Models::E212MNCEntry])
      expect(restored.items.map(&:to_hash)).to eq(edition.items.map(&:to_hash))
      expect(restored.provenance.as_of_issue).to eq(1170)
    end

    it 'renders through Liquid with one row per item and the as-of issue' do
      small = Ituob::Models::RegisterEdition.new(
        provenance: edition.provenance, items: edition.items.first(3)
      )
      template = Liquid::Template.parse(
        '{{ e.provenance.as_of_issue }}:{% for i in e.items %}{{ i.mcc_mnc_codes }};{% endfor %}'
      )

      expect(template.render!('e' => small))
        .to eq("1170:#{small.items.map(&:mcc_mnc_codes).join(';')};")
    end

    it 'rejects unknown registers, issues and unsupported registers with clear errors' do
      expect { provider.edition(register: 'nope', as_of: 1170) }
        .to raise_error(described_class::UnknownRegisterError, /Unknown register "nope"; known: .*e212-mnc/)
      expect { provider.edition(register: 'e212-mnc', as_of: 99_999) }
        .to raise_error(described_class::UnknownIssueError, 'Unknown OB issue 99999')
      expect { provider.edition(register: 'e212-mnc', as_of: 'latest') }
        .to raise_error(described_class::UnknownIssueError, /must be an OB issue number/)
      expect { provider.edition(register: 'e212-mnc', as_of: register.seed_issue - 1) }
        .to raise_error(described_class::UnknownIssueError, /no edition before its seed issue/)
      expect { provider.edition(register: 'nnp', as_of: 1170) }
        .to raise_error(Ituob::Projections::RegisterItems::UnsupportedRegisterError)
    end
  end

  describe '#history' do
    let(:key) { state.key_history.max_by { |_k, changes| changes.size }.first }
    let(:history) { provider.history(register: 'e212-mnc', key: key, as_of: 1170) }

    it 'returns the replay-recorded changes for the key in order with provenance' do
      expected = state.key_history.fetch(key)

      expect(history).to be_a(Ituob::Models::RegisterKeyHistory)
      expect(expected.size).to be > 1
      expect(history.key).to eq(key)
      expect(history.entries.map { |e| [e.type.value, e.ob_issue_no, e.identifier.code] })
        .to eq(expected.map { |c| [c.type, c.ob_issue_no, c.identifier.code] })
      expect(history.provenance.as_of_issue).to eq(1170)
      expect(history.provenance.register_id).to eq('E212_MNC')
    end

    it 'reports active and deleted membership from replayed state' do
      active = state.active_keys.first
      expect(provider.history(register: 'e212-mnc', key: active, as_of: 1170).membership).to eq('active')

      dnic = Ituob::Projections::RegisterItems.new(
        register: Ituob::Catalogs::Registers.find('X121_DNIC')
      ).state_at(1170)
      deleted = dnic.deleted_keys.reject { |k| dnic.has_key?(k) }.first
      expect(deleted).not_to be_nil
      result = provider.history(register: 'x121-dnic', key: deleted, as_of: 1170)

      expect(result.membership).to eq('deleted')
      expect(result.entries.map { |e| e.type.value }).to include('SUP')
    end

    it 'reports lapsed membership for a lapsed key' do
      lapsed_state = Ituob::Registers::State.new(
        register_id: 'E212_MNC', at_ob_issue: 1170, entries: { 'A' => { 'mcc_mnc_codes' => 'A' } },
        lapsed_keys: Set['A'], deleted_keys: Set.new, history: []
      )
      result = Ituob::Projections::KeyHistory.new(register: register, state: lapsed_state).for_key('A')

      expect(result.membership).to eq('lapsed')
      expect(result.entries).to eq([])
    end

    it 'follows touched keys even when printed identifiers are table positions' do
      cc_provider = described_class.new
      cc_register = Ituob::Catalogs::Registers.find('E164_CC')
      cc_state = Ituob::Projections::RegisterItems.new(register: cc_register).state_at(1170)
      key, changes = cc_state.key_history.find { |k, cs| cs.any? { |c| c.identifier.code != k } }

      expect(key).not_to be_nil
      result = cc_provider.history(register: 'e164-cc', key: key, as_of: 1170)
      expect(result.entries.map { |e| e.identifier.code }).to eq(changes.map { |c| c.identifier.code })
      expect(result.entries.map(&:key).uniq).to eq([key])
    end

    it 'limits history to changes at or before as_of' do
      earlier = provider.history(register: 'e212-mnc', key: key, as_of: register.seed_issue)

      expect(earlier.entries.map(&:ob_issue_no).max).to be <= register.seed_issue
      expect(earlier.entries.size).to be < history.entries.size
    end

    it 'rejects an unknown key, register and issue with clear errors' do
      expect { provider.history(register: 'e212-mnc', key: 'no such key', as_of: 1170) }
        .to raise_error(Ituob::Projections::KeyHistory::UnknownKeyError,
                        'Register E212_MNC has no key "no such key" as of issue 1170')
      expect { provider.history(register: 'nope', key: key, as_of: 1170) }
        .to raise_error(described_class::UnknownRegisterError)
      expect { provider.history(register: 'e212-mnc', key: key, as_of: 99_999) }
        .to raise_error(described_class::UnknownIssueError)
    end
  end
end
