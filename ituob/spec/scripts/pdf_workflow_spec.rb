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
end
