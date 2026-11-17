# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "json"
require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe "PDF workflow catalog isolation" do
  let(:workflow) do
    YAML.load_file(File.expand_path("../../../.github/workflows/pdf.yml", __dir__), aliases: true)
  end
  let(:plan) { workflow.fetch("jobs").fetch("plan") }
  let(:list) { plan.fetch("steps").find { |step| step["id"] == "list" } }
  let(:only) { "" }
  let(:docs) { %w[T-SP-A-2011 T-SP-B-2012] }
  let(:outputs) do
    Dir.mktmpdir do |dir|
      docs.each { |doc| FileUtils.mkdir_p(File.join(dir, "documents", doc)) }
      output = File.join(dir, "outputs")
      stdout, stderr, status = Open3.capture3(
        { "ONLY" => only, "GITHUB_OUTPUT" => output },
        "bash", "-c", list.fetch("run"), chdir: dir
      )
      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      File.readlines(output, chomp: true).to_h { |line| line.split("=", 2) }
    end
  end

  it "publishes every shard as the catalog for an unrestricted run" do
    expect(JSON.parse(outputs.fetch("docs"))).to eq(docs)
    expect(outputs.fetch("count")).to eq("2")
    expect(outputs.fetch("artifact-name")).to eq("publications")
  end

  context "with a manual subset" do
    let(:only) { docs.first }

    it "keeps the partial manifest out of the catalog artifact" do
      expect(JSON.parse(outputs.fetch("docs"))).to eq([docs.first])
      expect(outputs.fetch("count")).to eq("1")
      expect(outputs.fetch("artifact-name")).to eq("publications-subset")
    end
  end

  context "with an explicit list of all publications" do
    let(:only) { docs.join(",") }

    it "reserves the catalog name for unrestricted runs" do
      expect(JSON.parse(outputs.fetch("docs"))).to eq(docs)
      expect(outputs.fetch("artifact-name")).to eq("publications-subset")
    end
  end

  it "passes the planned artifact name to the final upload" do
    expect(plan.fetch("outputs").fetch("artifact-name")).to eq("${{ steps.list.outputs.artifact-name }}")
    upload = workflow.fetch("jobs").fetch("publications").fetch("steps").last
    expect(upload.fetch("uses")).to eq("actions/upload-artifact@v4")
    expect(upload.fetch("with").fetch("name")).to eq("${{ needs.plan.outputs.artifact-name }}")
  end

  it "reports the merged catalog without blocking initial publication on fidelity failures" do
    job = workflow.fetch("jobs").fetch("typesetting")
    expect(job.fetch("needs")).to eq(%w[plan publications])
    steps = job.fetch("steps")
    download = steps.find { |step| step["uses"] == "actions/download-artifact@v4" }
    expect(download.fetch("with").fetch("name")).to eq("${{ needs.plan.outputs.artifact-name }}")
    report = steps.find { |step| step["id"] == "report" }
    expect(report.fetch("continue-on-error")).to be(true)
    expect(report.fetch("run")).to include("pdf_typesetting_report.rb", "--verify")
    upload = steps.last
    expect(upload.fetch("if")).to eq("always()")
    expect(upload.fetch("with").fetch("name")).to eq("typesetting-report")
  end

  it "installs standalone static Chinese fonts while preserving Arabic fonts" do
    steps = workflow.fetch("jobs").fetch("render").fetch("steps")
    install = steps.find { |step| step["name"] == "Install the Chinese and Arabic fonts" }
    expect(install.fetch("run")).to include(
      'for weight in Regular Bold',
      'https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/SubsetOTF/SC/NotoSansSC-$weight.otf',
      'Fontist::Manifest.from_hash({"Noto Sans SC" => ["Regular", "Bold"]}, locations: true)',
      'abort "Chinese static fonts not registered"',
      'fontist install "Noto Naskh Arabic" --accept-all-licenses'
    )
    sources = Dir[File.expand_path("../../../documents/T-SP-*/*-C.adoc", __dir__)]
    expect(sources.size).to eq(7)
    sources.each do |source|
      expect(File.read(source)).to include(":language: zh\n", ":fonts: Noto Sans SC\n")
    end
  end

end
