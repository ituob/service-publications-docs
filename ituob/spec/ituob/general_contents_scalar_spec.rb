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
end
