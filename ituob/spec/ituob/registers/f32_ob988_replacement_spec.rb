# frozen_string_literal: true

require "yaml"
require "date"

# Pins why the register-state integrity gate reports 212 asserted-add findings
# for F32_TDI at OB 988 (G11, ituob/service-publications-docs#95): the OB 988
# Egypt REP replaces the whole network list, and prints offices that the OB 980
# printed seed does not hold. They are later printed additions, not missing seed rows.
RSpec.describe "F.32 OB 988 whole-network replacement" do
  let(:root) { File.expand_path("../../../..", __dir__) }
  let(:seed) { YAML.unsafe_load_file(File.join(root, "datasets/980-F.32/publication.yaml")) }
  let(:change) { YAML.unsafe_load_file(File.join(root, "datasets/980-F.32/changes/0988-0001-REP-UNMY.yaml")) }

  let(:seed_egypt_codes) do
    seed.fetch("allocations").select { |entry| entry["network_roa"].to_s.include?("Egypt") }
      .map { |entry| entry["office_code"] }.compact.uniq
  end
  let(:replacement_codes) { change.fetch("data").fetch("entries").map { |entry| entry["office_code"] }.uniq }

  it "is flagged as replacing the whole Egyptian network" do
    expect(change.fetch("data")["replaces_network"]).to be(true)
  end

  it "prints 212 offices the OB 980 seed does not hold, keeps 49 and withdraws 31" do
    expect(seed_egypt_codes.length).to eq(80)
    expect((seed_egypt_codes - replacement_codes).length).to eq(31)
    expect(replacement_codes.length).to eq(261)
    expect((replacement_codes - seed_egypt_codes).length).to eq(212)
    expect((replacement_codes & seed_egypt_codes).length).to eq(49)
  end

  it "adds four-letter UN codes, plus URRG exactly as OB 988 prints it" do
    added = replacement_codes - seed_egypt_codes
    expect(added.reject { |code| code.match?(/\AUN[A-Z]{2}\z/) }).to eq(["URRG"])
  end
end
