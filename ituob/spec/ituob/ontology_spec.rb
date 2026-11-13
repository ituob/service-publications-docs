# frozen_string_literal: true

require 'spec_helper'
require 'lutaml/lml'

RSpec.describe 'Ituob model ontology (ituob/ontology/messages.lml)' do
  ONTOLOGY_PATH = File.expand_path('../../lib/ituob/ontology/messages.lml', __dir__)

  # Ruby attributes typed :hash have no LML primitive — the ontology
  # declares them String. Attribute NAMES and cardinality are still
  # guarded; only the type check is waived.
  TYPE_WAIVERS = {
    'F400Entry' => %w[helpdesk autoanswer contact_address].freeze,
    # Registers::Change keeps `type` as a coerced String at runtime;
    # the ontology twin declares the ActionType enum.
    'RegisterChange' => %w[type].freeze,
  }.freeze

  # Register-layer patch classes live under Ituob::Registers (they
  # carry behavior) but their shapes belong to the ontology. Named
  # RegisterChange to avoid the actions-tree Ituob::Models::Change.
  REGISTER_PATCH_CLASSES = {
    'RegisterChange' => Ituob::Registers::Change,
    'Identifier' => Ituob::Registers::Identifier,
  }.freeze

  let(:document) { Lutaml::Lml.parse_document(File.open(ONTOLOGY_PATH)) }
  # Reuse the boot-time compiler so the anonymous compiled classes in
  # the parity check are the very objects registered under Ituob::Models.
  let(:compiler) { Ituob::Models::Compiled.compiler }

  def eager_load_models
    Ituob::Models.constants.each { |c| (Ituob::Models.const_get(c) rescue nil) }
  end

  # lutaml's attribute macro injects non-model constants into the
  # defining namespace; they are not part of the ontology.
  LUTAML_INJECTED = %w[ACTION_CLASS GENERATOR_STATE_KEY].freeze

  # Only module-level constants — Class#constants would leak lutaml's
  # inherited internals (ClassMethods, ...). Sibling classes
  # (IssueContact, TextAction, ...) live at module level once their host
  # file is eager-loaded.
  def serializable_classes(mod)
    out = []
    mod.constants.sort.each do |const|
      next if LUTAML_INJECTED.include?(const.to_s)

      k = mod.const_get(const)
      case k
      when Class
        out << [const.to_s, k] if k < Lutaml::Model::Serializable
      when Module
        out.concat(serializable_classes(k))
      end
    end
    out
  end

  def type_repr(attr, anonymous_names = {})
    return attr.type.to_s unless attr.type.is_a?(Class)

    attr.type.name ? attr.type.name.split('::').last : anonymous_names[attr.type]
  end

  def shape_of(klass, anonymous_names = {})
    klass.attributes.transform_values do |attr|
      [type_repr(attr, anonymous_names), attr.collection?]
    end
  end

  before(:all) do
    Ituob::Models.constants.each { |c| (Ituob::Models.const_get(c) rescue nil) }
  end

  it 'parses with zero RS 3001 validation violations' do
    expect(Lutaml::Lml::Validator.violations(document)).to be_empty
  end

  it 'declares every Ruby model class and nothing else' do
    eager_load_models
    # Identifier is also compiled for projection attributes; the
    # behavioral Registers::Identifier keeps the same guarded shape.
    ruby_names = (serializable_classes(Ituob::Models).map(&:first) - LUTAML_INJECTED)
      .concat(REGISTER_PATCH_CLASSES.keys).uniq.sort
    lml_names = document.classes.map { |c| c.name.to_s }.sort
    expect(lml_names).to eq(ruby_names)
  end

  describe 'attribute parity per class' do
    before(:all) do
      Ituob::Models.constants.each { |c| (Ituob::Models.const_get(c) rescue nil) }
    end

    it 'matches names, types and cardinality exactly' do
      eager_load_models
      hand_classes = serializable_classes(Ituob::Models).to_h
        .merge(REGISTER_PATCH_CLASSES)
      failures = []

      hand_classes.each do |name, hand|
        compiled = compiler.compiled_classes[name]
        failures << "#{name}: missing from compiled ontology" && next unless compiled

        # Compiled class-ref types are anonymous classes; name them via
        # the compiler's registry so both sides speak in ontology names.
        anonymous_names = compiler.compiled_classes.invert
        hand_shape = shape_of(hand, anonymous_names)
        compiled_shape = shape_of(compiled, anonymous_names)
        waivers = TYPE_WAIVERS.fetch(name, [])

        (hand_shape.keys | compiled_shape.keys).each do |attr|
          h = hand_shape[attr]
          c = compiled_shape[attr]
          if h.nil? || c.nil?
            failures << "#{name}.#{attr}: present #{h ? 'hand-only' : 'ontology-only'}"
            next
          end
          failures << "#{name}.#{attr}: cardinality hand=#{h[1]} ontology=#{c[1]}" if h[1] != c[1]
          next if waivers.include?(attr.to_s)

          if h[0] != c[0]
            failures << "#{name}.#{attr}: type hand=#{h[0]} ontology=#{c[0]}"
          end
        end
      end

      expect(failures).to be_empty, "ontology drift:\n  #{failures.join("\n  ")}"
    end
  end

  describe 'compiled projection types' do
    let(:action_type) { compiler.compiled_classes.fetch('ActionType') }
    let(:provenance) do
      Ituob::Models::ProjectionProvenance.new(
        register_id: 'E212_MNC', as_of_issue: 1170, seed_issue: 1162,
        last_change_issue: 1169
      )
    end
    let(:history_entry) do
      Ituob::Models::KeyHistoryEntry.new(
        key: '234 | 15', type: action_type.MOD, ob_issue_no: 1169,
        identifier: Ituob::Models::Identifier.new(code: '234 | 15')
      )
    end
    let(:edition) do
      Ituob::Models::RegisterEdition.new(
        provenance: provenance,
        items: [{ 'mcc' => '234', 'mnc' => '15', 'operator' => { 'en' => 'Example' } }],
        lapsed_keys: ['234 | 01', '234 | 02'],
        deleted_keys: ['234 | 03'], key_history: [history_entry]
      )
    end

    %i[provenance history_entry edition].each do |model_name|
      %i[yaml json].each do |format|
        it "round-trips #{model_name} through lutaml-model #{format}" do
          model = public_send(model_name)
          serialized = model.public_send("to_#{format}")
          restored = model.class.public_send("from_#{format}", serialized)

          expect(restored).to be_a(model.class)
          expect(JSON.parse(restored.to_json)).to eq(JSON.parse(model.to_json))
        end
      end
    end

    it 'hydrates nested compiled types and preserves composite keys' do
      restored = Ituob::Models::RegisterEdition.from_yaml(edition.to_yaml)

      expect(restored.provenance).to be_a(Ituob::Models::ProjectionProvenance)
      expect(restored.key_history.first).to be_a(Ituob::Models::KeyHistoryEntry)
      expect(restored.key_history.first.identifier).to be_a(Ituob::Models::Identifier)
      expect(restored.key_history.first.key).to eq('234 | 15')
      expect(restored.key_history.first.type.value).to eq('MOD')
      expect(restored.items).to eq(edition.items)
    end

    it 'round-trips query identifiers through the compiled identifier type' do
      history_entry.identifier = Ituob::Models::Identifier.new(
        query: { 'field' => 'mcc', 'value' => '234', 'operator' => 'equals' }
      )
      restored = Ituob::Models::KeyHistoryEntry.from_yaml(history_entry.to_yaml)

      expect(restored.identifier.query).to eq(history_entry.identifier.query)
      expect(restored.identifier.code).to be_nil
    end

    it 'uses the ontology action vocabulary for key history' do
      expect(history_entry.validate).to be_empty
      history_entry.type.value = 'UNKNOWN'
      expect(history_entry.type.validate).not_to be_empty
    end

    it 'round-trips seed-only provenance and empty collections' do
      seed_provenance = Ituob::Models::ProjectionProvenance.new(
        register_id: 'E212_MNC', as_of_issue: 1162, seed_issue: 1162
      )
      seed_edition = Ituob::Models::RegisterEdition.new(provenance: seed_provenance)
      restored = Ituob::Models::RegisterEdition.from_yaml(seed_edition.to_yaml)

      expect(restored.provenance.last_change_issue).to be_nil
      expect(restored.provenance.as_of_issue).to eq(1162)
      expect(restored.items).to eq([])
      expect(restored.lapsed_keys).to eq([])
      expect(restored.deleted_keys).to eq([])
      expect(restored.key_history).to eq([])
    end

    context 'with a small replay' do
      let(:changes) do
        [
          Ituob::Registers::Change.new(
            type: 'SEED', register_id: 'F1', ob_issue_no: 669,
            identifier: { code: 'seed' }, data: [{ 'code' => 'Z', 'label' => 'seed' }]
          ),
          Ituob::Registers::Change.new(
            type: 'ADD', register_id: 'F1', ob_issue_no: 700,
            identifier: { code: 'A' }, data: { 'label' => 'added' }
          ),
          Ituob::Registers::Change.new(
            type: 'ADD', register_id: 'F1', ob_issue_no: 701,
            identifier: { code: 'M' }, data: { 'label' => 'kept' }
          ),
          Ituob::Registers::Change.new(
            type: 'DEL', register_id: 'F1', ob_issue_no: 702, identifier: { code: 'A' }
          ),
          Ituob::Registers::Change.new(
            type: 'MOD', register_id: 'F1', ob_issue_no: 800,
            identifier: { code: 'M' }, data: { 'label' => 'future' }
          )
        ]
      end
      let(:source) { Ituob::Registers::InlineChangeSource.new(register_id: 'F1', changes: changes) }
      let(:state) do
        Ituob::Registers::Replay.new(register_id: 'F1', key_field: 'code', source: source).at_issue(710)
      end
      let(:replayed_edition) do
        Ituob::Models::RegisterEdition.new(
          provenance: Ituob::Models::ProjectionProvenance.new(
            register_id: state.register_id, as_of_issue: state.at_ob_issue,
            seed_issue: source.seed_issue, last_change_issue: state.last_issue
          ),
          items: state.active_entries.values,
          lapsed_keys: state.lapsed_keys.to_a.sort,
          deleted_keys: state.deleted_keys.to_a.sort,
          key_history: state.history.map do |change|
            Ituob::Models::KeyHistoryEntry.new(
              key: change.seed? ? 'Z' : change.identifier.code,
              type: action_type.public_send(change.type), ob_issue_no: change.ob_issue_no,
              identifier: Ituob::Models::Identifier.new(code: change.identifier.code)
            )
          end
        )
      end

      it 'carries the pinned state, provenance and history through mapped serialization' do
        expect(state.errors).to be_empty
        restored = Ituob::Models::RegisterEdition.from_json(replayed_edition.to_json)

        expect(restored.provenance.register_id).to eq('F1')
        expect(restored.provenance.as_of_issue).to eq(710)
        expect(restored.provenance.seed_issue).to eq(669)
        expect(restored.provenance.last_change_issue).to eq(702)
        expect(restored.items).to eq(
          [{ 'code' => 'Z', 'label' => 'seed' }, { 'code' => 'M', 'label' => 'kept' }]
        )
        expect(restored.lapsed_keys).to eq([])
        expect(restored.deleted_keys).to eq(['A'])
        expect(restored.key_history.map do |entry|
          [entry.key, entry.type.value, entry.ob_issue_no, entry.identifier.code]
        end)
          .to eq([['Z', 'SEED', 669, 'seed'], ['A', 'ADD', 700, 'A'],
                  ['M', 'ADD', 701, 'M'], ['A', 'DEL', 702, 'A']])
        expect(restored.class.attributes.keys).to contain_exactly(
          :provenance, :items, :lapsed_keys, :deleted_keys, :key_history
        )
      end
    end
  end
end
