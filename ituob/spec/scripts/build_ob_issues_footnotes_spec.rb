# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

RSpec.describe "printed footnotes in issue patches" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }

  it "keeps existing glossary notes alongside the newly parsed footnotes" do
    Dir.mktmpdir("printed-footnotes") do |output|
      code = <<~'CODE'
        stats = Hash.new(0)
        stats[:by_amendment_target] = Hash.new { |h, k| h[k] = { structured: 0, text: 0, errors: 0 } }
        Thread.current[:build_stats] = stats
        %w[989 1186].each do |issue|
          process_amendments(issue, File.join(ITU_OB_DATA_PATH, issue), File.join(ARGV[0], issue), stats)
        end
      CODE
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-r", File.join(repo_root, "scripts/build_ob_issues.rb"), "-e", code, output
      )
      expect(status.success?).to be(true), stderr
      e212 = YAML.load_file(File.join(output, "989/e212-mnc/003-ADD.yaml"))
      expect(e212.dig("data", "notes").join(" ")).to include("As from 31 August 2011", "Mobile Country Code")
      expect(e212.dig("data", "entries", 0, "effective_date")).to eq("31 August 2011")
      e164 = Dir.glob(File.join(output, "1186/e164-cc/*.yaml")).map { |path| YAML.load_file(path) }
      notes = e164.flat_map { |patch| patch.dig("data", "notes") }.join(" ")
      expect(notes).to include("k United Nations", "t Reserved", "Notes common to Numerical")
    end
  end
end
