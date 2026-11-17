# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

# Template gaps measured by scripts/pdf_fidelity_report.rb against the official
# ITU PDFs: PP.RES.21 printed two entries twice, and T.35B printed English
# labels in French and Spanish and dropped what an administration with no
# assignment authority has.
RSpec.describe 'PDF fidelity templates' do
  let(:root) { File.expand_path('../../..', __dir__) }

  def template(path) = Liquid::Template.parse(File.read(File.join(root, path)))

  describe 'T-SP-PP.RES.21-2011/_table.liquid' do
    let(:tpl) { template('documents/T-SP-PP.RES.21-2011/_table.liquid') }
    let(:metadata) { { 'title' => { 'en' => 'T' }, 'locale' => [{ 'key' => 'note', 'en' => 'N' }] } }

    def render(count)
      data = (1..count).map { |n| { 'number' => n, 'geographic_area' => { 'en' => "Country#{n}" } } }
      tpl.render!('data' => data, 'metadata' => metadata, 'lang' => 'en')
    end

    def numbers(out) = out.scan(/\| (\d+) \| Country/).flatten.map(&:to_i)

    it 'prints every entry exactly once, whatever the count' do
      [116, 118, 7].each do |count|
        expect(numbers(render(count)).sort).to eq((1..count).to_a)
      end
    end

    it 'fills the first column down, then the second, an odd count leaving the last right cell empty' do
      expect(numbers(render(5))).to eq([1, 4, 2, 5, 3])
    end
  end

  describe 'T-SP-T.35B-2012/_table.liquid' do
    let(:tpl) { template('documents/T-SP-T.35B-2012/_table.liquid') }
    let(:authority) do
      { 'terminal_type' => ['h'], 'contact_name' => 'C', 'organization' => 'O', 'department' => 'D',
        'address' => 'A', 'telephone' => 'T', 'fax' => 'F', 'email' => 'M', 'related_links' => 'L',
        'last_updated' => '2006-03-10' }
    end
    let(:data) do
      [{ 'country' => 'iso-3166:de', 'administration_name' => 'Adm', 'manufactures_htv' => true,
         'assignment_authority' => [authority], 'last_updated' => '2006-03-10' },
       { 'country' => 'iso-3166:bw', 'administration_name' => 'Bots', 'manufactures_htv' => false,
         'assignment_authority' => [], 'last_updated' => '2004-08-31' }]
    end
    let(:acronyms) { { 'de' => { 'en' => 'Germany', 'fr' => 'Allemagne', 'es' => 'Alemania' }, 'bw' => { 'en' => 'Botswana', 'fr' => 'Botswana', 'es' => 'Botswana' } } }

    def render(lang) = tpl.render!('data' => data, 'acronyms' => acronyms, 'lang' => lang)

    it 'prints the English labels, authority-less administration and date as the official PDF does' do
      out = render('en')
      expect(out).to include('| Name of Administration: |', 'YES', 'NO', 'Assignment authority: None designated',
                             '| Information updated: | 10 March 2006', '| Information updated: | 31 August 2004')
    end

    it 'prints French labels, answers, months and the no-authority text' do
      out = render('fr')
      expect(out).to include('| Nom de l’Administration: |', 'OUI', 'NON', "Autorité responsable de l'attribution:",
                             "Aucune n'a été désignée", '| Mise à jour des informations: | 10 mars 2006',
                             '| Mise à jour des informations: | 31 août 2004')
      expect(out).not_to match(/Name of Administration|Information updated|\bYES\b/)
    end

    %w[fr es].each do |lang|
      it "prints no date in #{lang} (as English does) when last_updated is nil, blank or not a real date" do
        [nil, '', 'garbage', '2006-13-40'].each do |bad|
          data.each { |c| c['last_updated'] = bad; c['assignment_authority'].each { |a| a['last_updated'] = bad } }
          out = render(lang)
          expect(out).to match(/\| (Mise à jour des informations|Información actualizada): \| *$/)
          expect(out).not_to match(/diciembre|décembre|garbage|13-40/)
        end
      end
    end

    it 'prints Spanish labels, answers, months and the no-authority text' do
      out = render('es')
      expect(out).to include('| Nombre de la administración: |', 'SÍ', 'Autoridad de asignación:',
                             'No se ha designado ninguna', '| Información actualizada: | 10 de marzo de 2006',
                             '| Información actualizada: | 31 de agosto de 2004')
      expect(out).not_to match(/Name of Administration|Information updated|\bYES\b/)
    end
  end

  describe 'T-SP-E.212A-2017/_tables.liquid' do
    let(:tpl) { template('documents/T-SP-E.212A-2017/_tables.liquid') }
    let(:mcc_dir) { File.join(root, 'datasets/1117-E.212A-MCCMNC') }

    def render(lang)
      tpl.render!('data' => [], 'metadata' => { 'title' => { lang => 'T' }, 'locale' => [] },
                  'data_mcc_mnc' => YAML.load_file(File.join(mcc_dir, 'data.yaml')),
                  'metadata_mcc_mnc' => YAML.load_file(File.join(mcc_dir, 'metadata.yaml')), 'lang' => lang)
    end

    it 'prints the status of a shared-MCC network in the document language, not the English key' do
      { 'ru' => 'Присвоен', 'zh' => '已指配', 'fr' => 'Attribué', 'es' => 'Asignado' }.each do |lang, word|
        out = render(lang)
        expect(out).to include("| Iridium Communications Inc | 901 03 | #{word}")
        expect(out).not_to match(/\| assigned$/)
      end
    end
  end
end
