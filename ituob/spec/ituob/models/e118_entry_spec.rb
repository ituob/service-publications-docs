# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'

RSpec.describe Ituob::Models::E118Entry do
  subject(:entry) { described_class.parse(document.tables.first.rows.first) }

  let(:paragraphs) do
    ['Contact Person', 'Contact Street'].map do |text|
      { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
    end
  end
  let(:contact_details) do
    ['Tel: +41 22 123', 'Fax: +41 22 456', 'E-mail: contact@example.com']
  end
  let(:contact_content) do
    paragraphs + contact_details.map do |text|
      { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
    end
  end
  let(:document) do
    cells = ['Switzerland', 'Example Telecom', '89 41 01'].map do |text|
      { 'type' => 'table_cell', 'content' => [
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
      ] }
    end
    cells << { 'type' => 'table_cell', 'content' => contact_content }
    cells << { 'type' => 'table_cell', 'content' => [
      { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => '1.I.2020' }] }
    ] }
    Prosereflect::Parser.parse_document(
      'type' => 'doc', 'content' => [
        { 'type' => 'table', 'content' => [{ 'type' => 'table_row', 'content' => cells }] }
      ]
    )
  end

  shared_examples 'a complete contact' do
    it 'extracts the contact, address and communication details' do
      expect(entry.contact).to eq('Contact Person')
      expect(entry.contact_address_1).to eq('Contact Street')
      expect(entry.contact_address_2).to be_nil
      expect(entry.tel).to eq(['+41 22 123'])
      expect(entry.fax).to eq(['+41 22 456'])
      expect(entry.email).to eq(['contact@example.com'])
    end
  end

  context 'with flat contact paragraphs' do
    include_examples 'a complete contact'

    it 'preserves the other printed columns' do
      expect(entry.country_or_area.en).to eq('Switzerland')
      expect(entry.company_name).to eq('Example Telecom')
      expect(entry.issue_id_number).to eq('89 41 01')
      expect(entry.effective_date).to eq('1.I.2020')
    end
  end

  ['E-mail: contact@example.com', 'E-mail : contact@example.com', 'E-mail:contact@example.com'].each do |email_line|
    context "with printed labels #{email_line.inspect}" do
      let(:contact_details) { ['Tel : +41 22 123', 'Fax : +41 22 456', email_line] }

      include_examples 'a complete contact'
    end
  end

  context 'with nested contact tables among paragraphs' do
    let(:contact_content) do
      tables = [
        [['Tel :', '+41 22 123'], ['Fax :', '+41 22 456']],
        [['E-mail :', 'contact@example.com']]
      ].map do |rows|
        { 'type' => 'table', 'content' => rows.map do |values|
          { 'type' => 'table_row', 'content' => values.map do |text|
            { 'type' => 'table_cell', 'content' => [
              { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
            ] }
          end }
        end }
      end
      paragraphs + [tables.first, { 'type' => 'paragraph' }, tables.last]
    end

    include_examples 'a complete contact'
  end

  context 'with contact values wrapped onto the next printed line' do
    let(:contact_details) do
      ['Tel: +358 294 440 500/', "\u00a0\u00a0\u00a0 +358 40 8668 582", 'Fax: +358 294 440 501',
       'E-mail: jerry@', "\u00a0\u00a0\u00a0\u00a0 marathontelecom.net"]
    end

    it 'keeps the second telephone number and completes the wrapped e-mail address' do
      expect(entry.tel).to eq(['+358 294 440 500/ +358 40 8668 582'])
      expect(entry.fax).to eq(['+358 294 440 501'])
      expect(entry.email).to eq(['jerry@marathontelecom.net'])
    end
  end

  context 'with a continuation that is not a number or an address' do
    let(:contact_details) { ['Tel: +358 294 440 500/', 'some free text', 'E-mail: a@b.org'] }

    it 'does not fold it into the telephone number' do
      expect(entry.tel).to eq(['+358 294 440 500/'])
      expect(entry.email).to eq(['a@b.org'])
    end
  end
end
