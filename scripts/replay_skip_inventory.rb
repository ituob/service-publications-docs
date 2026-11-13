#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob/support'
require 'ituob/registers'
require 'ituob/catalogs'
require 'csv'
require 'fileutils'

# The ledger consumes Replay's own errors, including its per-row conflicts.
# Neither patch application nor the skip message format is duplicated here.
module ReplaySkipInventory
  COLUMNS = %w[register ob_issue patch error class print_ref].freeze
  CLASSES = {
    'S' => 'Seed or route from an existing dataset',
    'E' => 'Engine rule (including seed-issue amendments already embodied)',
    'T' => 'Correct the action type from print',
    'D' => 'Mis-filed patch',
    'G' => 'Documented source or extraction gap'
  }.freeze

# Reviewed evidence from 100-03-conflicts.md, checked against the printed
# corpus. A skip is classified only when its register, issue, action, patch
# identifier AND the conflicting row key all match a rule; refs maps each
# reviewed row key to its printed line in itu-ob-data/issues/<issue>/. A rule
# with a String ref is a textual patch with no row keys. This is classification
# evidence, not a list of expected counts.
Rule = Struct.new(:register, :issue, :type, :code, :category, :refs, keyword_init: true) do
  def patch?(change)
    [register, issue, type, code] ==
      [change.register_id, change.ob_issue_no, change.type, change.identifier.code]
  end

  def print_ref(error)
    return "#{issue}/amendments.yaml:#{refs}" if refs.is_a?(String)

    key = refs.keys.find { |candidate| error.include?("key #{candidate.inspect} ") }
    "#{issue}/amendments.yaml:#{refs.fetch(key)}" if key
  end
end

UKRAINE_REFS = {
  'UKRAINE | UX- - | ' => 944, 'UKRAINE | UX- - | UXCK' => 1018,
  'UCRANIA | UX- - | UXCG' => 1072, 'UCRANIA | UX- - | UXCV' => 1126,
  'UCRANIA | UX- - | UXDP' => 1180, 'UCRANIA | UX- - | UXDC' => 1234,
  'UCRANIA | UX- - | UXGR' => 1288, 'UCRANIA | UX- - | UXIF' => 1342,
  'UCRANIA | UX- - | UXHR' => 1396, 'UCRANIA | UX- - | UXHS' => 1450,
  'UCRANIA | UX- - | UXHM' => 1504, 'UCRANIA | UX- - | UXKG' => 1558,
  'UCRANIA | UX- - | UXKM' => 1612, 'UCRANIA | UX- - | UXKR' => 1666,
  'UCRANIA | UX- - | UXKV' => 1720, 'UCRANIA | UX- - | UXLK' => 1774,
  'UCRANIA | UX- - | UXLC' => 1828, 'UCRANIA | UX- - | UXLV' => 1882,
  'UCRANIA | UX- - | UXMR' => 1936, 'UCRANIA | UX- - | UXMK' => 1990,
  'UCRANIA | UX- - | UXOD' => 2044, 'UCRANIA | UX- - | UXPL' => 2098,
  'UCRANIA | UX- - | UXRV' => 2152, 'UCRANIA | UX- - | UXSV' => 2206,
  'UCRANIA | UX- - | UXSF' => 2260, 'UCRANIA | UX- - | UXSU' => 2314,
  'UCRANIA | UX- - | UXTR' => 2368, 'UCRANIA | UX- - | UXUG' => 2422,
  'UCRANIA | UX- - | UXVC' => 2476, 'UCRANIA | UX- - | UXYL' => 2530,
  'UCRANIA | UX- - | UXZP' => 2584, 'UCRANIA | UX- - | UXZT' => 2638,
  'UCRANIA | UX- - | UXKX' => 2692
}.freeze

EVIDENCE = [
  Rule.new(register: 'E118_IIN', issue: 1161, type: 'SUP', code: '89 420 06', category: 'E',
           refs: { '89 420 06' => 573 }),
  Rule.new(register: 'Q708_ISPC', issue: 1109, type: 'SUP', code: '2-125-6', category: 'E',
           refs: { '2-125-6' => 627, '2-248-4' => 669, '5-245-2' => 711,
                   '5-245-6' => 753, '5-251-0' => 795, '6-237-4' => 837 }),
  Rule.new(register: 'Q708_ISPC', issue: 1109, type: 'SUP', code: '4-082-6', category: 'E',
           refs: { '4-082-6' => 1189, '4-086-0' => 1231, '4-086-1' => 1273 }),
  Rule.new(register: 'F32_TDI', issue: 1004, type: 'LIR', code: '1004-0001', category: 'D',
           refs: '213-330'),
  Rule.new(register: 'Q708_ISPC', issue: 1167, type: 'SUP',
           code: 'Genza SA Rue de Lausanne 37 1201 GENEVE', category: 'D',
           refs: { 'Genza SA Rue de Lausanne 37 1201 GENEVE' => 3166 }),
  Rule.new(register: 'E164_CC', issue: 1217, type: 'LIR', code: '1217-0002', category: 'G',
           refs: '148-156'),
  Rule.new(register: 'F32_TDI', issue: 1013, type: 'SUP', code: 'MALAISIE', category: 'G',
           refs: { 'MALAISIE | MA- | MAAS MAIP MAJB MAKU MAKO MAKB MAKL MATG MAKN MAKG MAMC MAPK MAPG MAPJ MASR MATP MAMX' => 1082 }),
  Rule.new(register: 'F32_TDI', issue: 1148, type: 'SUP', code: 'UKRAINE', category: 'G',
           refs: UKRAINE_REFS),
  Rule.new(register: 'X121_DNIC', issue: 1081, type: 'SUP', code: '206 1', category: 'G',
           refs: { '206 1' => 8845 })
].freeze

ROOT = File.expand_path('..', __dir__)

  # Keep the DirectoryChangeSource loader and ordering; only retain provenance
  # while it yields the already-loaded Change to Replay.
  class Source < Ituob::Registers::DirectoryChangeSource
    def each_sorted
      return enum_for(:each_sorted) unless block_given?

      @paths = {}.compare_by_identity
      super do |change|
        @paths[change] = @loaded_path
        yield change
      end
    end

    def path_for(change)
      @paths.fetch(change)
    end

    private

    def load_yaml(path)
      @loaded_path = path
      super
    end
  end

  # report_skip remains the sole producer of skip messages and counts. Retain
  # the associated Change so identical row errors can still name their file.
  class Replay < Ituob::Registers::Replay
    attr_reader :skipped_changes

    def initialize(**options)
      super
      @skipped_changes = []
    end

    private

    def report_skip(builder, change, error)
      super
      @skipped_changes << change
    end
  end

def self.classify(change, error: '')
  rule = EVIDENCE.find { |candidate| candidate.patch?(change) && candidate.print_ref(error) }
  unless rule
    raise "Unclassified skip: #{change.register_id} OB #{change.ob_issue_no} " \
          "#{change.identifier.to_hash.inspect} (#{error})"
  end

  [rule.category, "itu-ob-data/issues/#{rule.print_ref(error)}"]
end

# Catalog seed paths are repo-relative; resolve them against the repository
# root so the result never depends on the working directory.
def self.source_for(entry)
  seed_dir = File.expand_path(entry.seed_path, ROOT)
  unless File.directory?(seed_dir) && File.file?(File.join(seed_dir, Source::SEED_FILENAME))
    raise "Missing seed directory or #{Source::SEED_FILENAME} for #{entry.register_id}: #{entry.seed_path}"
  end

  Source.new(
    register_id: entry.register_id, seed_path: seed_dir,
    seed_issue: entry.seed_issue, key_field: entry.key_field
  )
end

def self.repo_relative(path)
  path.to_s.delete_prefix("#{ROOT}/")
end

def self.rows_for(entry, source: nil)
  source ||= source_for(entry)
  replay = Replay.new(
    register_id: entry.register_id, key_field: entry.key_field, source: source,
    fallback_key_fields: entry.fallback_key_fields
  )
  state = replay.current
  unless state.errors.length == replay.skipped_changes.length
    raise "Non-skip replay errors in #{entry.register_id}: #{state.errors.inspect}"
  end

  state.errors.zip(replay.skipped_changes).map do |error, change|
    category, print_ref = classify(change, error: error)
    patch = source.respond_to?(:path_for) ? source.path_for(change) : change.reference
    raise "Missing patch provenance for #{change.register_id} OB #{change.ob_issue_no}" unless patch

    [entry.register_id, change.ob_issue_no, repo_relative(patch), error, category, print_ref]
  end
end

  def self.collect
    rows = Ituob::Catalogs::Registers.all.flat_map do |entry|
      next [] if entry.external? || entry.seed_path.nil?

      rows_for(entry)
    end
    rows.sort_by { |row| row.first(4) }
  end

  def self.tsv(rows)
    CSV.generate(col_sep: "\t") do |csv|
      csv << COLUMNS
      rows.each do |row|
        bad = row.map(&:to_s).find { |field| field.match?(/[\t\r\n]/) }
        raise "TSV field contains TAB, CR or LF: #{bad.inspect}" if bad

        csv << row
      end
    end
  end

  def self.adoc(rows)
    register_counts = rows.group_by(&:first).transform_values(&:length)
    class_counts = rows.group_by { |row| row[4] }.transform_values(&:length)
    <<~ADOC
      = Replay-skip inventory (G6/G7)

      Generated by `ruby scripts/replay_skip_inventory.rb` from the catalog registers'
      dataset seeds and `changes/` directories. Regenerate both files with that command
      from the repository root. The adjacent `replay-skips.tsv` is the complete ledger.
      Counts are from one current-state replay per seeded, non-external register;
      historical snapshots are not replayed again and do not multiply the counts.
      Each row is one skip reported by `Replay#report_skip`, including each conflicting
      row of a multi-row patch. Error text is copied verbatim from `State#errors`.
      Registers without a seed or marked external have no dataset replay.
      Unclassified skips or unexpected replay errors fail generation instead of being
      silently assigned a source-gap class. Print references identify the transcribed
      wording in `itu-ob-data`, not a PDF page or a reconstructed seed.

      Total skips: *#{rows.length}*.

      == Totals per register

      [cols="1,1",options="header"]
      |===
      |Register |Skips
      #{register_counts.sort.map { |register, count| "|#{register} |#{count}" }.join("\n")}
      |===

      == Totals per class

      The S/E/T/D/G classes follow `100-03-conflicts.md`. That investigation's
      pre-#66 counts are historical baselines; they are not expected totals here.

      [cols="1,4,1",options="header"]
      |===
      |Class |Meaning |Skips
      #{CLASSES.map { |category, label| "|#{category} |#{label} |#{class_counts.fetch(category, 0)}" }.join("\n")}
      |===

      == Source gaps and interpretation

      * Note s (old inventory #8): `itu-ob-data/issues/1217/amendments.yaml:148-156`
        prints a textual LIR saying no three-digit trial identification code is
        temporarily assigned. There is no item row to seed. The preceding withdrawal
        is at lines 28-32; the original trial allocation is in
        `itu-ob-data/issues/1161/amendments.yaml:1240-1260`.
        There is no Note s dataset. This source gap remains documented even when
        the current replay produces no skip for it; documentation adds no TSV row.
      * X.121 206 1 (old inventory #26):
        `itu-ob-data/issues/1081/amendments.yaml:8735-8741` prints the withdrawal,
        with the row at line 8845. It is absent from the OB 977 seed and intervening
        patches through OB 1080. The printed OB 977 seed table is unavailable in
        repository text. Other rows in that patch apply independently; their successful
        withdrawals are not skips.
      * F.32: the OB 980 seed ends at ISRAEL, omitting MALAYSIA and UKRAINE.
        Withdrawals are printed in `itu-ob-data/issues/1013/amendments.yaml:767-1082`
        and `itu-ob-data/issues/1148/amendments.yaml:680-2692`. The first patch also
        aggregates office codes; the second contains individual rows and an empty
        office-code heading. Each reported row remains a separate skip. The ledger
        records these extraction/source gaps without changing the seed or patch data.
      * Seed-issue suppressions (E) target keys already absent from the post-amendment
        annex. Mis-filed patches (D) carry a different register's printed columns.
        These classes describe the evidence; the inventory does not change replay.
    ADOC
  end

  def self.write(output_root: File.expand_path('../docs/normalization', __dir__))
    rows = collect
    FileUtils.mkdir_p(output_root)
    File.write(File.join(output_root, 'replay-skips.tsv'), tsv(rows))
    File.write(File.join(output_root, 'replay-skips.adoc'), adoc(rows))
    puts "Replay skips: #{rows.length}"
  end
end

ReplaySkipInventory.write if $PROGRAM_NAME == __FILE__
