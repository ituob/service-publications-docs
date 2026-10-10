# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'

RSpec.describe 'Ituob::Models amendment classes' do
  described_classes = {
    'E118Amendment' => Ituob::Models::E118Amendment,
    'DPAmendment' => Ituob::Models::DPAmendment,
    'E164ACNAmendment' => Ituob::Models::E164ACNAmendment,
    'E164CCAmendment' => Ituob::Models::E164CCAmendment,
    'E212MNCAmendment' => Ituob::Models::E212MNCAmendment,
    'E218TRCCAmendment' => Ituob::Models::E218TRCCAmendment,
    'F32TDIAmendment' => Ituob::Models::F32TDIAmendment,
    'F400Amendment' => Ituob::Models::F400Amendment,
    'M1400Amendment' => Ituob::Models::M1400Amendment,
    'Q708ISPCAmendment' => Ituob::Models::Q708ISPCAmendment,
    'Q708SANCAmendment' => Ituob::Models::Q708SANCAmendment,
    'T35NAAmendment' => Ituob::Models::T35NAAmendment,
    'X121DNICAmendment' => Ituob::Models::X121DNICAmendment,
  }

  described_classes.each do |name, klass|
    describe name do
      it 'inherits from GeneralMessage or Amendment' do
        expect(klass.ancestors).to include(Ituob::Models::Amendment).or include(Ituob::Models::GeneralMessage)
      end

      it 'parses a minimal real document into an Amendment' do
        doc = { 'type' => 'doc', 'content' => [
          { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 1 TEST ADD' }] },
        ] }
        parsed = klass.parse(doc)
        expect(parsed).to be_a(Ituob::Models::Amendment)
        expect(parsed.actions).to be_an(Array)
      end

      it 'is registered in AMENDMENT_TYPE_TO_CLASS' do
        registry = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS
        expect(registry.values).to include(klass), "#{name} not in registry"
      end
    end
  end
end

RSpec.describe 'Ituob::Models TextAmendment' do
  let(:klass) { Ituob::Models::TextAmendment }

  it 'is registered for textual publication types' do
    registry = Ituob::Models::OldIssue::AMENDMENT_TYPE_TO_CLASS
    # NNP is semantic since TODO.complete/50.
    %w[RR.25.1 BUREAUFAX].each do |pub|
      expect(registry[pub]).to be(klass), "#{pub} should map to TextAmendment"
    end
  end

  it 'parses a document verbatim (TextAmendment)' do
    doc = { 'type' => 'doc', 'content' => [
      { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Free text amendment' }] },
    ] }
    parsed = klass.parse(doc)
    expect(parsed).to be_a(Ituob::Models::Amendment)
  end
end

RSpec.describe 'Ituob::Models entry classes' do
  entry_classes = [
    Ituob::Models::E118Entry,
    Ituob::Models::DPEntry,
    Ituob::Models::E164ACNEntry,
    Ituob::Models::E164CCEntry,
    Ituob::Models::E164BEntry,
    Ituob::Models::E212MNCEntry,
    Ituob::Models::E218TRCCEntry,
    Ituob::Models::F32TDIEntry,
    Ituob::Models::F400Entry,
    Ituob::Models::M1400Entry,
    Ituob::Models::Q708ISPCEntry,
    Ituob::Models::Q708SANCEntry,
    Ituob::Models::T35NAEntry,
    Ituob::Models::X121DNICEntry,
  ]

  entry_classes.each do |klass|
    describe klass.name do
      it 'inherits from Lutaml::Model::Serializable' do
        expect(klass.ancestors).to include(Lutaml::Model::Serializable)
      end

      it 'has at least one attribute' do
        expect(klass.attributes).not_to be_empty
      end
    end
  end
end

RSpec.describe 'Ituob::Models general message classes' do
  general_classes = [
    Ituob::Models::GeneralIptn,
    Ituob::Models::GeneralIpns,
  ]

  general_classes.each do |klass|
    describe klass.name do
      it 'parses a minimal real document into a GeneralMessage' do
        doc = { 'type' => 'doc', 'content' => [
          { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'P 1 TEST ADD' }] },
        ] }
        parsed = klass.parse(doc)
        expect(parsed).to be_a(Ituob::Models::GeneralMessage)
      end

      it 'is in GENERAL_TYPE_TO_CLASS' do
        registry = Ituob::Models::OldIssue::GENERAL_TYPE_TO_CLASS
        expect(registry.values).to include(klass), "#{klass.name} not in general registry"
      end
    end
  end
end
