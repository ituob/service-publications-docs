# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob::SourceDocuments::LegacyDocConverter do
  let(:fixture) { File.expand_path('../../fixtures/legacy_doc/paragraph_and_table.doc', __dir__) }

  describe '.read (Open3 stubbed)' do
    let(:docx_document) do
      Ituob::SourceDocuments::Document.new(source_path: '/tmp/x.docx', paragraphs: ['Para'], tables: [])
    end
    let(:calls) { [] }

    def stub_soffice(success:, write_docx:)
      allow(Open3).to receive(:capture2e) do |*cmd|
        calls << cmd
        outdir = cmd[cmd.index('--outdir') + 1]
        File.write(File.join(outdir, 'issue.docx'), 'docx') if write_docx
        ['soffice output', instance_double(Process::Status, success?: success)]
      end
    end

    it 'runs headless soffice into a tmpdir and hands the .docx to DocxReader' do
      stub_soffice(success: true, write_docx: true)
      allow(Ituob::SourceDocuments::DocxReader).to receive(:read).and_return(docx_document)

      document = described_class.read('/data/issue.doc')

      cmd = calls.fetch(0)
      outdir = cmd[cmd.index('--outdir') + 1]
      expect(cmd).to eq(['soffice', "-env:UserInstallation=file://#{outdir}/profile", '--headless',
                         '--convert-to', 'docx', '--outdir', outdir, '/data/issue.doc'])
      expect(Ituob::SourceDocuments::DocxReader).to have_received(:read).with(File.join(outdir, 'issue.docx'))
      expect(document.source_path).to eq('/data/issue.doc')
      expect(document.conversion).to eq(:soffice)
    end

    it 'removes the tmpdir after a conversion' do
      stub_soffice(success: true, write_docx: true)
      allow(Ituob::SourceDocuments::DocxReader).to receive(:read).and_return(docx_document)

      described_class.read('/data/issue.doc')

      outdir = calls.fetch(0)[calls.fetch(0).index('--outdir') + 1]
      expect(Dir.exist?(outdir)).to be(false)
    end

    it 'raises ConversionError and removes the tmpdir when soffice fails' do
      stub_soffice(success: false, write_docx: false)

      expect { described_class.read('/data/issue.doc') }
        .to raise_error(described_class::ConversionError, /issue\.doc.*soffice output/)
      outdir = calls.fetch(0)[calls.fetch(0).index('--outdir') + 1]
      expect(Dir.exist?(outdir)).to be(false)
    end

    it 'raises ConversionError when soffice exits 0 without writing a .docx' do
      stub_soffice(success: true, write_docx: false)

      expect { described_class.read('/data/issue.doc') }
        .to raise_error(described_class::ConversionError)
    end
  end

  describe 'DocReader path selection' do
    it 'uses the converter when soffice is on PATH' do
      converted = Ituob::SourceDocuments::Document.new(paragraphs: [], tables: [], conversion: :soffice)
      allow(described_class).to receive_messages(available?: true, read: converted)

      expect(Ituob::SourceDocuments::DocReader.read('/data/issue.doc')).to be(converted)
    end

    it 'falls back to textutil (paragraphs only) when soffice is absent' do
      allow(described_class).to receive(:available?).and_return(false)
      allow(Open3).to receive(:capture2) do |*cmd|
        File.write(cmd[cmd.index('-output') + 1], "First para\n\nSecond para\n")
        ['', instance_double(Process::Status, success?: true)]
      end

      document = Ituob::SourceDocuments::DocReader.read('/data/issue.doc')

      expect(Open3).to have_received(:capture2).with('textutil', '-convert', 'txt', '-output', anything,
                                                     '/data/issue.doc')
      expect(document.paragraphs).to eq(['First para', 'Second para'])
      expect(document.tables).to eq([])
      expect(document.conversion).to eq(:textutil)
    end
  end

  describe 'converting the Word 97 fixture', if: described_class.available? do
    it 'keeps the paragraph and the table rows' do
      document = Ituob::SourceDocuments::DocReader.read(fixture)

      expect(document.conversion).to eq(:soffice)
      expect(document.paragraphs).to include('Operational Bulletin legacy fixture.')
      expect(document.tables.first.rows.map(&:cells)).to eq([%w[Country Code], %w[Ruritania 999]])
    end
  end
end
