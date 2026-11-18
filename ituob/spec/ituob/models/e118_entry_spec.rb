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
  let(:company_lines) { ['Example Telecom'] }
  let(:contact_details) do
    ['Tel: +41 22 123', 'Fax: +41 22 456', 'E-mail: contact@example.com']
  end
  let(:contact_content) do
    paragraphs + contact_details.map do |text|
      { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
    end
  end
  let(:document) do
    cells = [['Switzerland'], company_lines, ['89 41 01']].map do |lines|
      { 'type' => 'table_cell', 'content' => lines.map do |text|
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
      end }
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
      expect(entry.contact_address).to eq(['Contact Street'])
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

  ['E-mail: contact@example.com', 'E-mail : contact@example.com', 'E-mail:contact@example.com',
   'E-Mail: contact@example.com'].each do |email_line|
    context "with printed labels #{email_line.inspect}" do
      let(:contact_details) { ['Tel : +41 22 123', 'Fax : +41 22 456', email_line] }

      include_examples 'a complete contact'
    end
  end

  context 'with nonbreaking spaces before contact label colons' do
    let(:contact_details) do
      ['Tel: +41 22 123', "Fax\u00a0: +41 22 456", "E-mail\u00a0: contact@example.com"]
    end

    it 'removes labels while retaining the fax and e-mail values' do
      expect(entry.tel).to eq(['+41 22 123'])
      expect(entry.fax).to eq(['+41 22 456'])
      expect(entry.email).to eq(['contact@example.com'])
      expect(entry.contact_address).to eq(['Contact Street'])
    end
  end

  context 'with a narrow no-break space before a fax colon' do
    let(:contact_details) do
      ['Tel: +41 22 123', "Fax\u202f: +41 22 456", 'E-mail: contact@example.com']
    end

    it 'classifies the fax and strips its label' do
      expect(entry.fax).to eq(['+41 22 456'])
      expect(entry.contact_address).to eq(['Contact Street'])
    end
  end

  context 'with a telephone label after the address on the same line' do
    let(:paragraphs) do
      ['Contact Person'].map do |text|
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
      end
    end
    let(:contact_details) do
      ['Contact Street 12 Tel: +40 21 344 84 00', 'Fax: +41 22 456', 'E-mail: contact@example.com']
    end

    it 'keeps the address prefix and extracts the telephone value' do
      expect(entry.contact_address).to eq(['Contact Street 12'])
      expect(entry.tel).to eq(['+40 21 344 84 00'])
    end
  end

  context 'with an uppercase value beginning with MOBILE' do
    let(:contact_details) { ['MOBILE PAY LIMITED'] }

    it 'preserves the full printed value' do
      expect(entry.tel).to be_nil
      expect(entry.contact_address).to eq(['Contact Street', 'MOBILE PAY LIMITED'])
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

  context 'with OB1203 nested contact label cells' do
    let(:contact_content) do
      rows = [
        [["Tel\u00a0:", '+33 1 75 85 00 00'], ["Fax\u00a0:", '+33 1 75 85 00 01']],
        [["E-mail\u00a0:", 'numerotation@legos.io']]
      ]
      nested_tables = rows.map do |table_rows|
        { 'type' => 'table', 'content' => table_rows.map do |values|
          { 'type' => 'table_row', 'content' => values.map do |text|
            { 'type' => 'table_cell', 'content' => [
              { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
            ] }
          end }
        end }
      end
      paragraphs + nested_tables
    end

    it 'classifies and strips the labels while retaining each value' do
      expect(entry.tel).to eq(['+33 1 75 85 00 00'])
      expect(entry.fax).to eq(['+33 1 75 85 00 01'])
      expect(entry.email).to eq(['numerotation@legos.io'])
      expect(entry.contact_address).to eq(['Contact Street'])
    end
  end

  context 'with the OB1215 nested e-mail label cell' do
    let(:paragraphs) do
      ['Arnaud Lecoeur', '29 Rue Pierre Paul Riquet', '31000 TOULOUSE'].map do |text|
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
      end
    end
    let(:contact_content) do
      row = ["E-mail\u00a0:", 'itu@aif-telecom.com'].map do |text|
        { 'type' => 'table_cell', 'content' => [{ 'type' => 'paragraph', 'content' => [
          { 'type' => 'text', 'text' => text }
        ] }] }
      end
      paragraphs + [{ 'type' => 'table', 'content' => [{ 'type' => 'table_row', 'content' => row }] }]
    end

    it 'retains the printed address and strips the e-mail label' do
      expect(entry.contact).to eq('Arnaud Lecoeur')
      expect(entry.contact_address).to eq(['29 Rue Pierre Paul Riquet', '31000 TOULOUSE'])
      expect(entry.email).to eq(['itu@aif-telecom.com'])
    end
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

  context 'with more printed address lines than the old fixed slots' do
    let(:company_lines) { ['Example Telecom', 'Street 1', 'P.O. Box 2', 'Town', 'ZIP 12345', 'Country'] }
    let(:paragraphs) do
      ['Contact Person', 'Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5', 'Line 6', 'Line 7'].map do |text|
        { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
      end
    end

    it 'keeps every company and contact address line in print order' do
      expect(entry.company_name).to eq('Example Telecom')
      expect(entry.company_address).to eq(['Street 1', 'P.O. Box 2', 'Town', 'ZIP 12345', 'Country'])
      expect(entry.contact_address).to eq(['Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5', 'Line 6', 'Line 7'])
      expect(entry.tel).to eq(['+41 22 123'])
    end
  end

  context 'with no printed address lines' do
    it 'leaves the company address unset' do
      expect(entry.company_address).to be_nil
    end
  end

  context 'with multiple international numbers on a labelled line' do
    let(:contact_details) do
      ['Tel: +44 1483 802503 (UK) +1 484-935-3130 (USA)',
       'Fax: +57 1 593 5399; +57 1 593 5206; +57 1 593 5201',
       'E-mail: contact@example.com', '+41 22 999']
    end

    it 'retains each number without moving subsequent email content into the phone list' do
      expect(entry.tel).to eq(['+44 1483 802503 (UK)', '+1 484-935-3130 (USA)'])
      expect(entry.fax).to eq(['+57 1 593 5399', '+57 1 593 5206', '+57 1 593 5201'])
      expect(entry.email).to eq(['contact@example.com'])
      expect(entry.contact).to eq('Contact Person')
      expect(entry.contact_address).to eq(['Contact Street'])
    end
  end

  context 'with an unlabelled fax continuation' do
    let(:contact_details) { ['Tel: +41 22 123', 'Fax +41 22 456', '+41 22 789', 'E-mail: contact@example.com'] }

    it 'keeps the continuation with the fax and preserves the telephone and address' do
      expect(entry.tel).to eq(['+41 22 123'])
      expect(entry.fax).to eq(['+41 22 456', '+41 22 789'])
      expect(entry.contact_address).to eq(['Contact Street'])
    end
  end
end
