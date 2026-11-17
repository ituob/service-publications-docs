# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../../../scripts/rr251_descriptions"

RSpec.describe Rr251Descriptions do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:paths) { Dir[File.join(root, "datasets/1154-RR.25.1/data/*.yaml")].sort }

  it "extracts a shared heading wrapped between station kinds" do
    source = "#Congo (Republic of the)\n#Amateur stations and\n#experimental stations: TN8AA-TN8ZZ\n"
    expect(described_class.extract(source)).to eq(
      "amateur" => "TN8AA-TN8ZZ", "experimental" => "TN8AA-TN8ZZ"
    )
  end

  it "retains Australia's lowercase experimental continuation through the sentence end" do
    source = File.read(File.join(root, "datasets/1154-RR.25.1/data/australia.yaml"))
    expect(described_class.extract(source).fetch("experimental")).to eq(
      "AX followed by a digit (2-9) and by 3 letters, the first one indicating the state or territory in which the station is situated."
    )
  end

  it "stops at genuine notes, codelists, footnotes and regex scaffolding" do
    ["Note: Use another prefix.", "Letters indicating the provinces:",
     "Digits indicating the zones:", "Numbers indicating city or region:",
     "Prefix  Digit  Suffix", "* For national amateurs.", "[VK|AX|VI][:area:]",
     "amateur:", "-"].each do |boundary|
      source = "# Experimental stations: AX followed by 3\n# letters, the first indicating the state.\n# #{boundary}\n# unrelated continuation\n"
      expect(described_class.extract(source)).to eq(
        "experimental" => "AX followed by 3 letters, the first indicating the state."
      )
    end
  end

  it "preserves all other YAML bytes, anchors and aliases when inserting a description" do
    source = <<~YAML
      # Amateur stations and
      # experimental stations: TN8AA-TN8ZZ
      groups:
        amateur: &general
        - regex: 'TN8[:upper:]{2}' # retain this comment
          criteria:
          - key: '1'
            value: TN8
        experimental: *general
    YAML
    updated = described_class.update(source)
    expect(updated).to eq(source.sub("    criteria:\n", "    description: \"TN8AA-TN8ZZ\"\n    criteria:\n"))
    expect(described_class.issues(updated)).to be_empty
    expect(described_class.update(updated)).to eq(updated)
    expect(YAML.safe_load(updated, aliases: true).dig("groups", "experimental", 0, "description")).to eq("TN8AA-TN8ZZ")
  end

  it "replaces a truncated description and preserves CRLF and unrelated Unicode bytes" do
    source = "# Experimental stations: AX followed by 3\r\n# letters.\r\n#\r\n# Français\r\ngroups:\r\n  experimental:\r\n  - regex: AX\r\n    description: \"AX followed by 3\"\r\n"
    expect(described_class.update(source)).to eq(source.sub('"AX followed by 3"', '"AX followed by 3 letters."'))
  end

  it "inserts on a new line when a regex is the final line without a newline" do
    source = "# Experimental stations: TN8AA-TN8ZZ\ngroups:\n  experimental:\n  - regex: TN8"
    updated = described_class.update(source)
    expect(updated).to eq(source + "\n    description: \"TN8AA-TN8ZZ\"\n")
    expect(described_class.issues(updated)).to be_empty
  end

  it "retains a multiline description's terminating newline" do
    source = "# Experimental stations: AX followed by 3 letters.\ngroups:\n  experimental:\n  - regex: AX\n    description: >\n      AX followed by 3\n    criteria: []\n"
    updated = described_class.update(source)
    expect(updated).to eq(source.sub(">\n      AX followed by 3\n", "\"AX followed by 3 letters.\"\n"))
    expect(described_class.issues(updated)).to be_empty
  end

  it "does not assign whole-kind prose to distinct named groups" do
    source = <<~YAML
      # Amateur stations: Two distinct licence classes.
      groups:
        amateur:
        - name: Advanced
          regex: A
        - name: Foundation
          regex: B
    YAML
    expect(described_class.update(source)).to eq(source)
    expect(described_class.issues(source)).to be_empty
    ambiguous = source.sub("    regex: A", "    description: Two distinct licence classes.\n    regex: A")
    expect(described_class.issues(ambiguous)).to include(/ambiguous groups/)
  end

  it "reports short or dangling prose even if a source comment itself is incomplete" do
    ["and", "AX followed by 3", "AX followed by letters and"].each do |prose|
      source = "# Experimental stations: #{prose}\ngroups:\n  experimental:\n  - regex: AX\n    description: #{prose}\n"
      expect(described_class.issues(source)).to include(/too short or ends mid-sentence/)
    end
  end

  it "keeps every corpus description equal to complete source prose and fills safe single groups" do
    expect(paths.length).to be > 90
    errors = paths.flat_map do |path|
      described_class.issues(File.read(path)).map { |issue| "#{File.basename(path)}: #{issue}" }
    end
    expect(errors).to be_empty, errors.join("\n")
  end

  it "rejects suspiciously short prose and dangling conjunctions or digits throughout the corpus" do
    paths.each do |path|
      groups = YAML.safe_load(File.read(path), aliases: true).fetch("groups", {})
      groups.each_value do |entries|
        entries.each do |entry|
          description = entry["description"]
          next unless description

          # Compact descriptions legitimately consist only of printed call-sign
          # ranges (Congo: TN8AA-TN8ZZ). A range can carry footnote markers, and
          # several complete ranges can occupy the same description. No arbitrary
          # short text, country name or prose fragment gets this exception.
          compact_ranges = /\A[A-Z0-9]+[-–][A-Z0-9]+\**(?: [A-Z0-9]+[-–][A-Z0-9]+\**)*\z/
          unless compact_ranges.match?(description)
            expect(description.split.length).to be >= 5, "#{path}: #{description}"
          end
          expect(description).not_to match(/\b(?:and|or|by|followed|\d+)\z/i), "#{path}: #{description}"
        end
      end
    end
  end
end
