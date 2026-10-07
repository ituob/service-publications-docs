# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/verifiers/parser_equivalence'

RSpec.describe Ituob::Verifiers::ParserEquivalence do
  def text_node(text)
    { 'type' => 'text', 'text' => text }
  end

  def paragraph(*texts)
    { 'type' => 'paragraph', 'content' => texts.map { |t| text_node(t) } }
  end

  def document(*paragraphs)
    { 'type' => 'doc', 'content' => paragraphs }
  end

  describe '.serialize' do
    it 'captures actions and notes of a real parsed amendment' do
      parsed = Ituob::Models::Q708SANCAmendment.parse(
        document(paragraph('P 12  Belgium  ADD')),
      )
      serialized = described_class.serialize(parsed)

      expect(serialized['actions']).to be_an(Array)
      expect(serialized['notes']).to be_an(Array)
    end

    it 'is deterministic for identical input' do
      doc = document(paragraph('P 12  Belgium  ADD'))
      first = described_class.serialize(Ituob::Models::Q708SANCAmendment.parse(doc))
      second = described_class.serialize(Ituob::Models::Q708SANCAmendment.parse(doc))

      expect(JSON.generate(first)).to eq(JSON.generate(second))
    end
  end

  describe '.diffs' do
    let(:base) do
      parsed = Ituob::Models::Q708SANCAmendment.parse(document(paragraph('P 12  Belgium  ADD')))
      { '1001' => described_class.serialize(parsed) }
    end

    it 'reports nothing for identical maps' do
      expect(described_class.diffs(base, base.dup)).to be_empty
    end

    it 'reports issues whose serialization changed' do
      changed = Ituob::Models::Q708SANCAmendment.parse(document(paragraph('P 13  Brazil  SUP')))
      current = { '1001' => described_class.serialize(changed) }

      expect(described_class.diffs(base, current)).to eq(['1001'])
    end

    it 'reports issues missing on either side' do
      expect(described_class.diffs(base, {})).to eq(['1001'])
      expect(described_class.diffs({}, base)).to eq(['1001'])
      expect(described_class.diffs(base, base.merge('1002' => {}))).to eq(%w[1002])
    end

    it 'returns sorted issue ids' do
      expect(described_class.diffs(base, base.merge('999' => {}, '1000' => {}))).to eq(%w[1000 999])
    end
  end
end
