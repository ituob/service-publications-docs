# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::Models::HashOrList do
  let(:row) { { 'mcc_mnc_codes' => '234 | 15', 'networks' => 'Example' } }

  { 'SEED' => true, 'ADD' => false }.each do |action, list|
    context "with #{action} data" do
      let(:data) { list ? [row] : row }
      let(:change) do
        Ituob::Registers::Change.new(
          type: action, register_id: 'E212_MNC', identifier: { 'code' => '234 | 15' },
          data: data, ob_issue_no: 1170
        )
      end

      %i[yaml json].each do |format|
        it "preserves the payload through replay and compiled #{format} mappings" do
          serialized = change.public_send("to_#{format}")
          compiled = Ituob::Models::RegisterChange.public_send("from_#{format}", serialized)
          restored = Ituob::Models::RegisterChange.public_send("from_#{format}", compiled.public_send("to_#{format}"))
          replayed = Ituob::Registers::Change.public_send("from_#{format}", compiled.public_send("to_#{format}"))

          expect(compiled.type.value).to eq(action)
          expect(compiled.data).to eq(data)
          expect(restored.to_hash).to eq(compiled.to_hash)
          expect(restored.data).to eq(data)
          expect(replayed.data).to eq(data)
        end
      end
    end
  end
end

RSpec.describe Ituob::Models::RegisterChange, 'empty payloads' do
  [[], {}].each do |data|
    it "retains an empty #{data.class} through the mapped projection" do
      replayed = Ituob::Registers::Change.new(
        type: 'SEED', register_id: 'E212_MNC', identifier: { 'code' => '__seed__' }, data: data
      )
      projected = described_class.from_yaml(replayed.to_yaml)
      restored = described_class.from_yaml(projected.to_yaml)

      expect(projected.data).to eq(data)
      expect(restored.data).to eq(data)
    end
  end
end
