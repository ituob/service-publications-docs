# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require File.expand_path('../../../scripts/pdf_typesetting_report', __dir__)
require_relative '../support/typesetting_pdf_fixture'

RSpec.describe PdfTypesettingReport do
  include TypesettingPdfFixture

  around do |example|
    Dir.mktmpdir('typesetting') do |dir|
      @artifact_dir = dir
      example.run
    end
  end

  let(:artifact_dir) { @artifact_dir }
  let(:pdf) { write_typesetting_manifest(artifact_dir) }
  let(:report) { described_class.run(pdf_dir: artifact_dir) }
  let(:failures) { report[:publications].first[:failures] }

  it 'passes a real self-contained A4 PDF and explicitly marks absent baselines' do
    write_typesetting_pdf(pdf)
    expect(report[:passed]).to be(true)
    expect(report[:publications].first[:fonts]).to all(include(embedded: true))
    expect(report[:publications].first[:roundtrip]).to include(matched: true)
    expect(report[:publications].first[:page_count_baseline]).to include(status: 'n/a')
  end

  it 'ignores title case changes introduced by cover typography' do
    write_typesetting_pdf(pdf, text: 'REGISTER')
    expect(report[:passed]).to be(true)
  end

  it 'fails a real PDF with a nonembedded Helvetica font' do
    write_typesetting_pdf(pdf, embedded: false)
    expect(failures).to include('font not embedded: Helvetica')
    expect(report[:passed]).to be(false)
  end

  it 'fails a real PDF whose extracted text includes a tofu square' do
    write_typesetting_pdf(pdf, text: "Register \u25A1")
    expect(failures).to include('missing-glyph/tofu characters: U+25A1')
    expect(report[:passed]).to be(false)
  end

  {
    'en' => 'Register', 'fr' => 'Répertoire', 'es' => 'Registro',
    'ru' => 'Список', 'zh' => '国际电信', 'ar' => 'سجل'
  }.each do |language, title|
    it "round-trips the known #{language} register title through a real PDF" do
      file = write_typesetting_manifest(artifact_dir, language: language, title: title)
      write_typesetting_pdf(file, text: title)
      expect(report[:publications].first[:roundtrip]).to include(expected: title, matched: true)
      expect(report[:passed]).to be(true)
    end
  end

  it 'normalizes Arabic presentation forms and directional controls without reversing logical text' do
    expect(described_class.normalized("\u202B\uFEB3\uFEA0\uFEDE\u202C")).to eq('سجل')
    expect(described_class.normalized('لجس')).not_to eq('سجل')
  end

  it 'round-trips Arabic presentation forms extracted from an actual PDF' do
    file = write_typesetting_manifest(artifact_dir, language: 'ar', title: 'سجل')
    write_typesetting_pdf(file, text: "\uFEB3\uFEA0\uFEDE")
    expect(report[:passed]).to be(true)
  end

  it 'uses the actual source heading when metadata has a different title' do
    file = write_typesetting_manifest(artifact_dir, standard: 'F.32', title: 'Different metadata title')
    manifest = File.join(artifact_dir, 'pdf', 'manifest.json')
    data = JSON.parse(File.read(manifest))
    data['publications'].first['edition_year'] = 2011
    File.write(manifest, JSON.generate(data))
    write_typesetting_pdf(file, text: 'LIST OF TELEGRAM DESTINATION INDICATORS')
    expect(report[:publications].first[:roundtrip]).to include(expected: 'LIST OF TELEGRAM DESTINATION INDICATORS', matched: true)
    expect(report[:publications].first[:roundtrip][:basis]).to end_with('documents/T-SP-F.32-2011/T-SP-F.32-2011-E.adoc')
  end

  it 'honors a source title attribute that overrides the document heading' do
    expected, basis = described_class.roundtrip_reference('standard' => 'SR.1', 'edition_year' => 2012, 'language' => 'en')
    expect(expected).to eq('SERVICE RESTRICTIONS')
    expect(basis).to end_with('T-SP-SR.1-2012-MSW-E.adoc')
  end

  it 'finds a source title in a filename with a publication suffix' do
    expected, basis = described_class.roundtrip_reference('standard' => 'F.1', 'edition_year' => 1998, 'language' => 'en', 'title' => 'Wrong metadata')
    expect(expected).to eq(File.readlines(File.expand_path('../../../documents/T-SP-F.1-1998/T-SP-F.1-1998-MSW-E.adoc', __dir__)).first.delete_prefix('= ').strip)
    expect(basis).to end_with('T-SP-F.1-1998-MSW-E.adoc')
  end

  it 'compares title words while ignoring punctuation mirrored by RTL extraction' do
    expect(described_class.roundtrip_text('((ITU-T E.118 (05/2006', 'ar')).to eq(described_class.roundtrip_text('(ITU-T E.118 (05/2006))', 'ar'))
    expect(described_class.roundtrip_text('ITU-T E.118 06/2005', 'ar')).not_to eq(described_class.roundtrip_text('ITU-T E.118 05/2006', 'ar'))
  end

  it 'preserves logical Arabic across a Latin bidi-run boundary with an omitted extraction space' do
    expect(described_class.roundtrip_text('SANCقائمة بالرموز', 'ar')).to eq(described_class.roundtrip_text('SANC قائمة بالرموز', 'ar'))
    expect(described_class.roundtrip_text('MNCفيما يتعلق', 'ar')).to eq(described_class.roundtrip_text('MNC فيما يتعلق', 'ar'))
    expect(described_class.roundtrip_text('SANCقائمة بالرموز', 'ar')).not_to eq(described_class.roundtrip_text('SANC ةمئاق بالرموز', 'ar'))
    expect(described_class.roundtrip_text('SANCقائمة بالرموز', 'ar')).not_to eq(described_class.roundtrip_text('SANCقائمة بالرمز', 'ar'))
  end

  it 'checks a native Arabic source heading when the source cover title is English' do
    file = write_typesetting_manifest(artifact_dir, standard: 'E.118', language: 'ar')
    manifest = File.join(artifact_dir, 'pdf', 'manifest.json')
    data = JSON.parse(File.read(manifest))
    data['publications'].first['edition_year'] = 2018
    File.write(manifest, JSON.generate(data))
    title, = described_class.roundtrip_reference(data['publications'].first)
    write_typesetting_pdf(file, text: title + ' سجل')
    expect(report[:publications].first[:script_roundtrip]).to include(expected: 'ملاحظة من مكتب تقييس الاتصالات', matched: false)
    expect(failures.join).to include('native-script source heading did not round-trip')
  end

  it 'accepts CJK line wrapping without accepting missing or reordered characters' do
    expect(described_class.roundtrip_text("国际\n电信", 'zh')).to eq('国际电信')
    expect(described_class.roundtrip_text('国际信电', 'zh')).not_to eq('国际电信')
  end

  it 'rejects a reversed Arabic register title even when Arabic letters are present' do
    file = write_typesetting_manifest(artifact_dir, language: 'ar', title: 'سجل')
    write_typesetting_pdf(file, text: 'لجس')
    expect(failures.join).to include('register title did not round-trip')
  end

  it 'rejects loss of the known register string despite other valid text' do
    write_typesetting_pdf(pdf, text: 'Other content')
    expect(failures.join).to include('register title did not round-trip')
  end

  it 'measures page geometry and rejects landscape and rotated pages' do
    write_typesetting_pdf(pdf, width: 841.89, height: 595.28, rotation: 90)
    expect(failures.join).to include('expected portrait A4', 'rotated 90')
  end

  it 'rejects a word bounding box crossing the page edge' do
    write_typesetting_pdf(pdf, x: 580)
    expect(failures.join).to include('text bounding boxes exceed page')
  end

  it 'fails a page-count mismatch against the historical official baseline' do
    file = write_typesetting_manifest(artifact_dir, standard: 'F.32')
    manifest = File.join(artifact_dir, 'pdf', 'manifest.json')
    data = JSON.parse(File.read(manifest))
    data['publications'].first['edition_year'] = 2011
    File.write(manifest, JSON.generate(data))
    write_typesetting_pdf(file)
    expect(failures.join).to include('page count 1 differs from baseline 47')
  end

  it 'accepts a manifest unpacked directly into the pdf root' do
    write_typesetting_pdf(pdf)
    flattened = described_class.run(pdf_dir: File.join(artifact_dir, 'pdf'))
    expect(flattened[:passed]).to be(true)
  end

  it 'does not skip unreadable PDFs or suppress independent measurement errors' do
    FileUtils.mkdir_p(File.dirname(pdf))
    File.write(pdf, 'invalid PDF')
    expect(failures.join).to include('fonts: pdffonts', 'text: pdftotext', 'geometry: pdfinfo', 'overflow: pdftotext')
  end

  it 'does not skip a missing manifest PDF' do
    pdf
    expect(report[:publications].size).to eq(1)
    expect(failures).to include('PDF is missing or empty')
  end

  it 'does not skip an unlisted PDF' do
    write_typesetting_pdf(pdf)
    write_typesetting_pdf(File.join(artifact_dir, 'extra.pdf'))
    expect(report[:passed]).to be(false)
    expect(report[:failures].join).to include('PDF absent from manifest')
  end

  it 'fails empty manifests rather than passing zero measurements' do
    pdf
    File.write(File.join(artifact_dir, 'pdf', 'manifest.json'), '{"publications":[]}')
    expect { report }.to raise_error(described_class::MeasurementError, /nonempty array/)
  end

  it 'rejects duplicate and unsafe manifest paths explicitly' do
    write_typesetting_pdf(pdf)
    manifest = File.join(artifact_dir, 'pdf', 'manifest.json')
    data = JSON.parse(File.read(manifest))
    data['publications'] << data['publications'].first.dup
    data['publications'] << { 'path' => '../outside.pdf', 'language' => 'en' }
    File.write(manifest, JSON.generate(data))
    expect(report[:publications].size).to eq(3)
    expect(report[:failures].join).to include('duplicate manifest path', 'unsafe or missing manifest path')
  end

  it 'returns zero under --verify for a passing artifact' do
    write_typesetting_pdf(pdf)
    expect(described_class.main(['--pdf-dir', artifact_dir, '--out-dir', File.join(artifact_dir, 'report'), '--verify'])).to eq(0)
  end

  it 'writes JSON and AsciiDoc and returns nonzero under --verify for bad PDFs' do
    write_typesetting_pdf(pdf, text: "Register \uFFFD")
    output = File.join(artifact_dir, 'report')
    expect(described_class.main(['--pdf-dir', artifact_dir, '--out-dir', output, '--verify'])).to eq(1)
    expect(JSON.parse(File.read(File.join(output, 'report.json')))['passed']).to be(false)
    expect(File.read(File.join(output, 'report.adoc'))).to include('FAIL', 'visual inspection is still required')
  end
end
