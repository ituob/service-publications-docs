# frozen_string_literal: true

require 'spec_helper'

# `contents` on a General message carries either a structured document
# (a mapping) or authored plain prose (a string). Each class below
# declares the field in messages.lml; the string must survive a
# read/write cycle as a string, and a mapping as the same mapping.
RSpec.describe 'General message contents accept text or structured data' do
  CONTENTS_CLASSES = %w[
    GeneralMessage
    GeneralApprovedRecommendations
    GeneralCallbackProcedures
    GeneralCustom
    GeneralIpns
    GeneralIptn
    GeneralMid
    GeneralMiscCommunications
    GeneralOrgChanges
    GeneralRunningAnnexes
    GeneralSancs
    GeneralServiceRestrictions
    GeneralTelephoneCommunication
    GeneralTelephoneServices
  ].freeze

  let(:structured) do
    { 'en' => { 'type' => 'doc', 'content' => [{ 'type' => 'paragraph' }] } }
  end

  CONTENTS_CLASSES.each do |name|
    describe name do
      let(:klass) { Ituob::Models.const_get(name) }

      it 'keeps scalar prose as the same string' do
        out = klass.from_yaml("contents: Plain prose.\n").to_hash
        expect(out['contents']).to eq('Plain prose.')
      end

      it 'keeps a structured mapping unchanged' do
        out = klass.from_hash('contents' => structured).to_hash
        expect(out['contents']).to eq(structured)
      end
    end
  end

  it 'round-trips a stored nested telephone communication unchanged' do
    path = File.join(OB_ISSUES_ROOT, '1069', 'telephone_service_2', '001.yaml')
    communication = YAML.load_file(path, permitted_classes: [Date, Time])
                        .fetch('contents').first.fetch('communications').first
    out = Ituob::Models::GeneralTelephoneCommunication.from_hash(communication).to_hash
    expect(out['contents']).to eq(communication['contents'])
  end

  describe 'a mapping loads as a plain Hash, as `:hash` did' do
    let(:msg) { Ituob::Models::GeneralMessage.from_hash('contents' => structured) }

    it 'returns a Hash from the reader' do
      expect(msg.contents).to be_a(Hash)
      expect(msg.contents['en']).to eq(structured['en'])
    end

    it 'compares and hashes equal messages as equal' do
      other = Ituob::Models::GeneralMessage.from_hash('contents' => structured)
      expect(msg).to eq(other)
      expect(msg.hash).to eq(other.hash)
    end

    it 'returns a Hash for GeneralMiscCommunications and the nested telephone class' do
      %w[GeneralMiscCommunications GeneralTelephoneCommunication].each do |name|
        expect(Ituob::Models.const_get(name).from_hash('contents' => structured).contents).to be_a(Hash)
      end
    end

    it 'still returns a scalar as a String' do
      expect(Ituob::Models::GeneralMessage.from_yaml("contents: Plain prose.\n").contents)
        .to eq('Plain prose.')
    end

    it 'renders through Liquid dot access' do
      require 'liquid'
      model = Ituob::Models::GeneralMiscCommunications.from_hash('contents' => { 'en' => 'hi' })
      out = Liquid::Template.parse('{{ m.contents.en }}')
                            .render({ 'm' => model.to_liquid }, exception_renderer: ->(e) { raise e })
      expect(out).to eq('hi')
    end
  end

  describe 'empty and invalid contents behave as with `:hash`' do
    let(:klass) { Ituob::Models::GeneralMessage }

    it 'serializes an empty mapping the way :hash did (key omitted)' do
      expect(klass.from_yaml("contents: {}\n").to_yaml).to eq("--- {}\n")
    end

    it 'serializes an empty string the way :hash did (key omitted)' do
      expect(klass.from_yaml("contents: ''\n").to_yaml).to eq("--- {}\n")
    end

    it 'rejects an array with the same error class as :hash' do
      expect { klass.from_yaml("contents: [a, b]\n") }.to raise_error(TypeError)
    end
  end
end
