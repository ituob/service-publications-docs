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
    ruby_names = (serializable_classes(Ituob::Models).map(&:first) - LUTAML_INJECTED).sort
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
end
