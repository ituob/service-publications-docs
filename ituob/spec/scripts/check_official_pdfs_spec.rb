# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require File.expand_path("../../../scripts/check_official_pdfs", __dir__)
require_relative "../support/official_pdf_gate_helpers"

RSpec.describe OfficialPdfGate do
  include OfficialPdfGateHelpers

  let(:root) { @gate_root }
  let(:key) { "F.32-2011-E" }
  let(:official_path) { "fixtures/official.pdf" }
  let(:metrics) do
    { "official_sha256" => Digest::SHA256.hexdigest("PDF"), "recall" => 0.9,
      "rows" => 0.5, "cells" => 0.75, "pages_official" => 10,
      "pages_generated" => 11, "page_drift" => 1 }
  end
  let(:comparison) { PdfFidelity::Result.new(10, 10, 0.9, 0.9, 0.9, 4, 2, 8, 6, 10, 11) }
  let(:report_dir) { File.join(root, "build/official-comparison") }
  let(:rows) { JSON.parse(File.read(File.join(report_dir, "scores.json"))) }
  let(:candidate) { JSON.parse(File.read(File.join(report_dir, "candidate-baseline.json"))) }
  let(:markdown) { File.read(File.join(report_dir, "scores.md")) }

  before do
    @gate_root = Dir.mktmpdir("official-gate")
    gate_source("F.32-2011")
    gate_generated(key)
    gate_write(official_path)
    gate_index(key => official_path)
    gate_baseline(key => metrics)
    allow(PdfFidelity).to receive(:compare).and_return(comparison)
  end

  after { FileUtils.remove_entry(root) }

  it "passes a reviewed baseline and writes unrounded candidate scores with counts and page pairs" do
    comparison.recall = 0.912345678901
    expect(gate_run).to eq(0)
    expect(rows).to contain_exactly(include("key" => key, "status" => "pass", "errors" => [],
                                          "rows_official" => 4, "rows_matched" => 2,
                                          "cells_official" => 8, "cells_matched" => 6))
    expect(candidate[key]).to eq(metrics.merge("recall" => 0.912345678901))
    expect(markdown).to include("2/4", "6/8", "10/11", "pass")
  end

  it "fails metric regressions and page drift while retaining comparison results" do
    comparison.recall = 0.8
    comparison.rows_matched = 1
    comparison.cells_matched = 5
    comparison.pages_generated = 12
    expect(gate_run).to eq(1)
    expect(rows.first["errors"].join("; ")).to include("recall declined", "rows declined", "cells declined",
                                                     "page_drift increased: 1 -> 2")
    expect(candidate[key]["recall"]).to eq(0.8)
  end

  it "allows tiny floating point differences within tolerance" do
    comparison.recall = 0.9 - 1e-10
    expect(gate_run).to eq(0)
  end

  it "handles inapplicable table metrics without treating null as zero" do
    comparison.rows_official = 0
    comparison.cells_official = 0
    gate_baseline(key => metrics.merge("rows" => nil, "cells" => nil))
    expect(gate_run).to eq(0)
    expect(candidate[key]).to include("rows" => nil, "cells" => nil)
    expect(markdown).to include("n/a")
    gate_baseline(key => metrics)
    expect(gate_run).to eq(1)
    updated_rows = JSON.parse(File.read(File.join(report_dir, "scores.json")))
    expect(updated_rows.first["errors"]).to include("rows declined: 0.5 -> n/a", "cells declined: 0.75 -> n/a")
  end

  it "fails a changed official hash even when metrics are unchanged" do
    gate_write(official_path, "changed official")
    expect(gate_run).to eq(1)
    expect(rows.first["errors"].join).to include("official SHA256 changed")
  end

  it "lists sources with no official PDF and passes when their generated PDF exists" do
    gate_index({})
    gate_baseline({})
    expect(gate_run).to eq(0)
    expect(rows).to contain_exactly(include("key" => key, "status" => "no official PDF", "errors" => []))
    expect(markdown).to include(key, "no official PDF")
    expect(candidate).to eq({})
    expect(PdfFidelity).not_to have_received(:compare)
  end

  it "fails when an official formerly covered by the baseline disappears" do
    gate_index({})
    expect(gate_run).to eq(1)
    expect(rows.first["errors"].join).to include("official PDF removed")
    expect(markdown).to include("no official PDF")
  end

  it "fails missing generated coverage even without an official PDF" do
    gate_index({})
    gate_baseline({})
    FileUtils.rm_rf(File.join(root, "generated"))
    FileUtils.mkdir_p(File.join(root, "generated"))
    expect(gate_run).to eq(1)
    expect(rows.first).to include("status" => "error", "errors" => ["missing generated PDF"])
    expect(markdown).to include("no official PDF")
  end

  it "fails missing generated PDFs for a paired row" do
    FileUtils.rm(gate_generated(key))
    expect(gate_run).to eq(1)
    expect(rows.first["errors"]).to eq(["missing generated PDF"])
  end

  it "continues comparing other rows after extraction errors" do
    gate_source("F.32-2011", "F")
    gate_generated("F.32-2011-F")
    gate_index(key => official_path, "F.32-2011-F" => official_path)
    gate_baseline(key => metrics, "F.32-2011-F" => metrics)
    allow(PdfFidelity).to receive(:compare).with(a_string_ending_with("-E.pdf"), anything).and_raise("extraction failed")
    expect(gate_run).to eq(1)
    expect(rows.map { |row| row["status"] }).to eq(%w[error pass])
    expect(rows.first["errors"]).to eq(["extraction failed"])
    expect(candidate.keys).to eq(["F.32-2011-F"])
  end

  it "requires review of each new paired row and emits its candidate" do
    gate_baseline({})
    expect(gate_run).to eq(1)
    expect(rows.first["errors"]).to eq(["no reviewed baseline"])
    expect(candidate).to eq(key => metrics)
  end

  it "limits coverage and lost-official checks to selected publication directories" do
    gate_source("SR.1-2012", "E", "-MSW")
    gate_baseline(key => metrics, "SR.1-2012-E" => metrics)
    expect(gate_run("--docs", "T-SP-F.32-2011")).to eq(0)
    expect(rows.map { |row| row["key"] }).to eq([key])
    expect(gate_run).to eq(1)
    all_rows = JSON.parse(File.read(File.join(report_dir, "scores.json")))
    expect(all_rows.last["errors"].join).to include("official PDF removed", "missing generated PDF")
  end

  it "discovers official PDFs named by convention" do
    gate_index({})
    path = gate_write("docs/pdf/official/T-SP-#{key}.pdf")
    expect(gate_run).to eq(0)
    expect(PdfFidelity).to have_received(:compare).with(anything, path)
  end

  it "rejects duplicate official mappings rather than choosing one" do
    gate_write("docs/pdf/official/T-SP-#{key}.pdf")
    expect { expect(gate_run).to eq(2) }.to output(/duplicate official mapping/).to_stderr
  end

  it "uses publication directory and language for MSW and OAS-MSW source stems" do
    gate_source("F.1-1998", "S", "-MSW")
    gate_source("T.35-2012", "F", "-OAS-MSW")
    gate_source("E.212A-2017", "A")
    gate_source("E.212A-2017", "C")
    gate_source("E.212A-2017", "R")
    keys = described_class.inventory(root, nil).map { |row| row["key"] }
    expect(keys).to contain_exactly(key, "F.1-1998-S", "T.35-2012-F", "E.212A-2017-A",
                                   "E.212A-2017-C", "E.212A-2017-R")
  end

  it "retains a vanished baseline source as a failing report row" do
    gate_baseline(key => metrics, "SR.1-2012-E" => metrics)
    expect(gate_run).to eq(1)
    expect(rows.last["errors"].join).to include("source missing", "official PDF removed")
  end

  it "reports a missing indexed official as a row error" do
    FileUtils.rm(File.join(root, official_path))
    expect(gate_run).to eq(1)
    expect(rows.first["errors"].join).to include("missing official PDF")
    expect(candidate).to eq({})
  end

  it "rejects invalid extracted page counts" do
    comparison.pages_generated = 0
    expect(gate_run).to eq(1)
    expect(rows.first["errors"]).to eq(["invalid extracted metrics or page count"])
  end

  it "fails empty official text rather than creating a misleading baseline candidate" do
    comparison.words_official = 0
    expect(gate_run).to eq(1)
    expect(rows.first["errors"]).to eq(["official PDF has no extractable words"])
    expect(candidate).to eq({})
  end

  it "rejects missing and invalid baseline configuration" do
    path = File.join(root, "docs/pdf/official-baseline.json")
    ["{", "[]", JSON.generate(key => metrics.reject { |metric, _| metric == "recall" }),
     JSON.generate(key => metrics.merge("recall" => "0.9"))].each do |content|
      File.write(path, content)
      expect { expect(gate_run).to eq(2) }.to output(/official PDF gate:/).to_stderr
    end
    FileUtils.rm(path)
    expect { expect(gate_run).to eq(2) }.to output(/official PDF gate:/).to_stderr
  end

  it "rejects invalid CLI arguments and unknown selected publications" do
    expect { expect(described_class.main([])).to eq(2) }.to output(/--generated DIR is required/).to_stderr
    expect { expect(gate_run("--bogus")).to eq(2) }.to output(/invalid option/).to_stderr
    expect { expect(gate_run("--docs", "T-SP-unknown")).to eq(2) }.to output(/unknown publication/).to_stderr
  end
end
