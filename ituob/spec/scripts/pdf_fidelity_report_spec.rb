# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require File.expand_path('../../../scripts/pdf_fidelity_report', __dir__)

# Exercises scripts/pdf_fidelity_report.rb on layout text fixtures (what
# `pdftotext -layout` prints); no PDF is read.
RSpec.describe PdfFidelity do
  subject(:mod) { described_class }

  let(:official) do
    <<~TXT
      Annex to ITU OB 991-E                  -2-
      1      Afghanistan         59     Latvia
      2      Albania             60     Lebanon
    TXT
  end

  def compare_texts(generated, official_text)
    allow(mod).to receive_messages(pages: 1)
    allow(mod).to receive(:text).with('gen.pdf').and_return(generated)
    allow(mod).to receive(:text).with('off.pdf').and_return(official_text)
    mod.compare('gen.pdf', 'off.pdf')
  end

  describe 'NBSP and invalid UTF-8 in pdftotext output' do
    let(:nbsp_rows) { "1\u00A0\u00A0Afghanistan\u00A0\u00A059\u00A0\u00A0Latvia\n" }

    it 'counts NBSP-padded rows and cells like space-padded ones' do
      r = compare_texts('', nbsp_rows)
      expect([r.rows_official, r.cells_official]).to eq([1, 4])
    end

    it 'does not raise on invalid UTF-8 and still counts the valid text' do
      bad = "caf\xE9   x\n".dup.force_encoding('UTF-8')
      r = nil
      expect { r = compare_texts(bad, "cafe   x\n") }.not_to raise_error
      expect(r.rows_official).to eq(1)
    end
  end

  describe '.lines' do
    it 'drops running heads and page marks but keeps content' do
      raw = "Annex to ITU OB No. 1-E   -1-\nService Publication Annex to ITU OB\n  - 3 -\n  –12–\nAfghanistan\n"
      expect(mod.lines(raw)).to eq(['Afghanistan'])
    end
  end

  describe '.tokens' do
    it 'lowercases, folds curly quotes and splits punctuation' do
      expect(mod.tokens(["Côte d’Ivoire (Rep.)"])).to eq(%w[côte d ivoire rep])
    end

    it 'treats every Han character as a word and keeps Arabic and Cyrillic words whole' do
      expect(mod.tokens(['国际电信 Россия عمان'])).to eq(%w[国 际 电 信 россия عمان])
    end

  end

  describe '.rows and .cells' do
    let(:lines) { ['1      Afghanistan         59     Latvia', 'wrapped tail', ''] }

    it 'keeps only lines of two or more cells, as words' do
      expect(mod.rows(lines)).to eq(['1 afghanistan 59 latvia'])
    end

    it 'splits those lines into cells' do
      expect(mod.cells(lines)).to eq(['1', 'afghanistan', '59', 'latvia'])
    end
  end

  describe '.overlap and .lcs' do
    it 'counts a repeated word once per occurrence on both sides' do
      expect(mod.overlap(%w[a a b], %w[a b b])).to eq(2)
    end

    it 'measures order: the same words reordered share a shorter subsequence' do
      expect(mod.lcs(%w[a b c d], %w[a b c d])).to eq(4)
      expect(mod.lcs(%w[a b c d], %w[d c b a])).to eq(1)
    end
  end

  describe '.compare' do
    it 'scores an identical text 1.0 on every layer' do
      r = compare_texts(official, official)
      expect([r.recall, r.precision, r.order, r.rows, r.cells]).to all(eq(1.0))
    end

    it 'scores rows and cells against the official count, so a row the generated PDF lacks costs recall' do
      generated = "1      Afghanistan         59     Latvia\n117    Bulgaria\n"
      r = compare_texts(generated, official)
      expect(r.rows_official).to eq(2)
      expect(r.rows).to eq(0.5)
      expect(r.cells).to eq(0.5)
    end

    it 'finds a value that moved to another column or row, which the row measure does not' do
      generated = "Afghanistan         1\nLatvia         59\nAlbania   2\nLebanon   60\n"
      r = compare_texts(generated, official)
      expect(r.rows).to eq(0.0)
      expect(r.cells).to eq(1.0)
      expect(r.recall).to eq(1.0)
    end

    it 'reports the word recall and precision of a name the template lost' do
      generated = "1      Afghanistan         59     Latvia\n2      Albania\n"
      r = compare_texts(generated, official)
      expect(r.words_official).to eq(8)
      expect(r.recall).to eq(6 / 8.0)
      expect(r.precision).to eq(1.0)
    end
  end

  describe '.pairs' do
    it 'pairs a generated PDF with the official one of the same publication and language only' do
      Dir.mktmpdir do |dir|
        gen = File.join(dir, 'gen', 'F.32-2011')
        off = File.join(dir, 'off')
        FileUtils.mkdir_p([gen, off])
        FileUtils.touch([File.join(gen, 'F.32-2011-E.pdf'), File.join(gen, 'F.32-2011-F.pdf'),
                         File.join(off, 'T-SP-F.32-2011-E.pdf')])
        expect(mod.pairs(File.join(dir, 'gen'), off).map(&:first)).to eq([['F.32-2011', 'E']])
      end
    end
  end

  describe '.table' do
    it 'prints a markdown row per publication and language, n/a where the official has no rows' do
      r = mod::Result.new(10, 10, 1.0, 1.0, 1.0, 0, 0, 0, 0, 4, 5)
      md = mod.table([[['SR.1-2012', 'E'], r]])
      expect(md).to include('| SR.1-2012 | E | 10 | 100.0 | 100.0 | 100.0 | 0 | n/a | n/a | 4/5 |')
    end
  end
end
