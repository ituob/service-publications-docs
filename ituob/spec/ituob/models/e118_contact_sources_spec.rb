# frozen_string_literal: true

require 'spec_helper'
require 'ituob/models'
require 'ituob/helpers'
require 'yaml'

RSpec.describe 'E118 printed contact layouts' do
  [
    [1017, '89 1 091', { fax: ['+ 1 678 338 5961'] }],
    [1017, '89 1 450', { fax: ['+1 970 867 3589'] }],
    [1017, '89 1 340', { fax: ['+1 620 424 3146'] }],
    [1036, '89 44 16', { contact_address: ["Mobile By Sainsbury's Limited", '33 Holborn', 'London', 'EC1N 2HT', 'United Kingdom'], tel: ['+44 747 2900 92'] }],
    [1056, '89 254 04', { contact_address: ['MOBILE PAY LIMITED', 'P.O Box 69768', 'NAIROBI 00400', 'Kenya'], tel: ['+254 722690000'] }],
    [1063, '89 254 04', { contact_address: ['Mobile Pay Limited', 'Wilson Airport, Slip Road,', 'off Langata Road', 'P.O. Box 69768', 'NAIROBI 00400'], tel: ['+254 722690000'] }],
    [1140, '89 46 08', { contact_address: ['SE-116 88 STOCKHOLM'], tel: ['+:        46 70 933 55 15'] }],
    [1258, '89 32 30', { contact: 'Mobile Vikings NV, Legal', contact_address: ['Kempische Steenweg 309/1', '3500 HASSELT'], tel: ['+32 456 130 547'] }],
    [1018, '89 60 30', { contact: 'Mr MD RADZI BIN DIN', tel: ['+60 3 7450 8822'], fax: ['+60 3 7947 2199'], email: ['mdradzin.din@packet-1.com'] }],
    [1027, '89 1 371', { contact: 'Mr Dave Wittekind', tel: ['+1 678 338 5971'], fax: ['+ 1 678 338 5961'], email: ['dwittekind@atni.com'] }],
    [1039, '89 351 07', { contact: 'Mr. Philipp Lemke', contact_address: ['Mundio Mobile (Portugal) Limited', '54 Marsh Wall', 'LONDON E14 9TP', 'United Kingdom'], tel: ['+44 207 5364 800'], fax: ['+44 207 0050 562'], email: ['legal@mundio.com'] }],
    [1137, '89 356 01', { tel: ['+356 2093 0533', '+356 9942 5155'] }],
    [1154, '89 57 123', { tel: ['+57 1 593 5399', '+57 1 593 5206', '+57 1 593 5201'] }],
    [1265, '89 883 13', { tel: ['+44 1483 802503 (UK)', '+1 484-935-3130 (USA)'] }],
    [1297, '89 1 346', { tel: ['+1 441 909 9035', '+1 441 704 9035'] }],
    [1348, '89 1 084', { tel: ['+8447464370', '+1 303 731 2000'] }],
    [1139, '89 382 03', { fax: ['+382 20 633 846'] }],
    [1152, '89 267 02', { fax: ['+267 397 2674'] }],
    [1152, '89 267 04', { fax: ['+267 391 3355'] }],
    [1334, '89 81 21', { contact: 'Mobile Business Strategy Department', contact_address: ['Mobile Business Division', 'OPTAGE BLDG, 19F 2-1-5- Shiromi, Chuo-ku', 'OSAKA, 540-8622'], tel: ['+81 6 7501 0864'] }],
  ].each do |issue, identifier, expected|
    context "with OB #{issue}, IIN #{identifier}" do
      let(:source) do
        data = YAML.load_file(File.join(FIXTURE_ROOT, issue.to_s, 'amendments.yaml'), permitted_classes: [Date, Time])
        data['messages'].find { |message| message.dig('target', 'publication') == 'E118_IIN' }['contents']['en']
      end
      let(:row) do
        Prosereflect::Parser.parse_document(source).tables.flat_map(&:rows).reverse.find do |candidate|
          candidate.cells[2]&.text_content&.gsub(/[[:space:]]+/, ' ')&.strip == identifier
        end
      end
      let(:entry) { Ituob::Models::E118Entry.parse(row) }

      it 'retains every printed communication value and the other columns' do
        expected.each { |field, value| expect(entry.public_send(field)).to eq(value) }
        expect(entry.country_or_area.en).to eq(row.cells[0].text_content.strip)
        expect(entry.company_name).to eq(row.cells[1].lines.first)
        expect(entry.company_address).to eq(row.cells[1].lines.drop(1).map { |line| line.gsub(/[[:space:]]/, ' ').strip }.reject(&:empty?))
        expect(entry.issue_id_number).to eq(identifier)
        if row.cells[4]
          expect(entry.effective_date).to eq(row.cells[4].text_content.gsub(/[[:space:]]/, ' ').strip)
        end
      end
    end
  end
end
