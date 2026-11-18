#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates docs/pdf/coverage-matrix.adoc (spd#89, task 1): one row per
# publication x language under documents/, with the register(s) its datasets
# feed, the edition year, the OB issue the edition was published at, and a flag
# when a register has changes newer than that edition.
#
#   ruby scripts/build_pdf_coverage_matrix.rb [--root DIR] [--out FILE]
#
# Everything is read from the tree (documents/ headers, datasets/ changes,
# catalogs/registers.yaml). The output carries no wall-clock value, so a rerun
# on the same tree is byte-identical. Never edit the output by hand.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'optparse'
require 'json'

module PdfCoverageMatrix
  LANGUAGES = %w[A C E F R S].freeze
  DOC_DIR = /\AT-SP-(?<standard>.+)-(?<year>\d{4})\z/
  DOC_FILE = /\A(?<stem>.+)-(?<lang>[#{LANGUAGES.join}])\.adoc\z/
  DATASET_REF = %r{datasets/(?<slug>[^/,\]]+)/[\w.-]+\.ya?ml}
  # Only a yaml2text/data2text block attribute line names datasets the render
  # reads; the same text in a comment or in prose does not.
  BLOCK_LINE = /\A\[\w*2text\b/
  PROVIDER_LINE = /\A\[lutaml_data,provider:ituob\.(?:edition|publication),[^,]+,options=(\{.*\})\]\s*\z/
  OUT_PATH = 'docs/pdf/coverage-matrix.adoc'

  Row = Struct.new(
    :standard, :year, :language, :file, :docnumber, :issue, :datasets,
    :published, :registers, :unmapped, :newest, :flag, :data_path, keyword_init: true
  )

  # A register as the catalog describes it, plus the newest OB issue whose
  # change is on disk (the seed issue when there are no later changes).
  Register = Struct.new(:slug, :seed_path, :seed_issue, :newest_issue, keyword_init: true)

  module_function

  def rows(root)
    registers = register_index(root)
    all = publications(root).flat_map { |dir| rows_for(root, dir, registers) }
    reject_duplicates(all)
    all
  end

  # The manifest identity is (standard, year, language); a second file for the
  # same key (for example a stem variant) would make two entries share a path.
  def reject_duplicates(rows)
    dups = rows.group_by { |r| [r.standard, r.year, r.language] }.select { |_, v| v.size > 1 }
    return if dups.empty?

    lines = dups.map { |k, v| "#{k.join(' ')}: #{v.map(&:file).join(', ')}" }
    raise ArgumentError, "duplicate publication x language rows:\n#{lines.join("\n")}"
  end

  def publications(root)
    Dir.children(File.join(root, 'documents')).sort.select do |name|
      DOC_DIR.match?(name) && File.directory?(File.join(root, 'documents', name))
    end
  end

  def rows_for(root, dir, registers)
    meta = DOC_DIR.match(dir)
    Dir.children(File.join(root, 'documents', dir)).sort.filter_map do |file|
      m = DOC_FILE.match(file)
      next unless m

      row_for(File.join(root, 'documents', dir, file), meta, m[:lang], registers)
    end
  end

  def row_for(path, meta, lang, registers)
    text = File.read(path, encoding: 'UTF-8')
    head = header(text)
    slugs = text.lines.grep(BLOCK_LINE).flat_map { |l| l.scan(DATASET_REF).flatten }.uniq.sort
    mapped, unmapped = slugs.partition { |s| registers.key?(s) }
    providers = provider_sources(text)
    regs = mapped.map { |s| registers.fetch(s) }
    provider_unmapped = []
    datasets = slugs.filter_map { |s| (n = s[/\A\d+/]) && [s, n.to_i] }
    providers.each do |args|
      source_datasets = args['datasets'] || args['dataset']
      if source_datasets
        Array(source_datasets).each do |dataset|
          reg = registers[dataset]
          regs << reg if reg
          provider_unmapped << dataset unless reg
          datasets << [dataset, Integer(args.fetch('as_of'))]
        end
      else
        reg = registers.values.find { |r| r.slug == args.fetch('register') }
        raise ArgumentError, "unknown provider register #{args['register']} in #{path}" unless reg

        regs << reg
        datasets << [File.basename(reg.seed_path), Integer(args.fetch('as_of'))]
      end
    end
    regs = regs.uniq(&:slug).sort_by(&:slug)
    datasets = datasets.to_h.sort
    issue = datasets.map(&:last).max
    Row.new(
      standard: meta[:standard], year: meta[:year], language: lang,
      file: File.basename(path), docnumber: head['docnumber'], issue: issue,
      datasets: datasets,
      published: head['published-date'], registers: regs, unmapped: (unmapped + provider_unmapped).uniq.sort,
      newest: regs.map(&:newest_issue).max, flag: flag(issue, regs, datasets),
      data_path: providers.empty? ? 'yaml2text' : (slugs.empty? ? 'provider' : 'mixed')
    )
  end

  # Only actual provider block headers contribute register/issue provenance.
  def provider_sources(text)
    text.lines.filter_map do |line|
      match = PROVIDER_LINE.match(line)
      JSON.parse(match[1]).fetch('arguments') if match
    end
  end

  # Document header attributes: the `:name: value` lines before the first blank
  # line after the title block ends, i.e. before the first section.
  def header(text)
    text.lines.take_while { |l| !l.start_with?('[') && !l.start_with?('==') }
        .filter_map { |l| l.match(/\A:(?<k>[\w-]+): ?(?<v>.*?)\s*\z/) }
        .to_h { |m| [m[:k], m[:v]] }
  end

  # Each register is compared with the issue of the dataset the document reads
  # for it; the as-of issue (the maximum) only decides the unknown case.
  def flag(issue, regs, datasets)
    return 'no register' if regs.empty?
    return 'unknown (no numbered dataset)' unless issue

    read = datasets.to_h
    newer = regs.select do |r|
      at = read[File.basename(r.seed_path)] || issue
      r.newest_issue > at
    end
    return 'current' if newer.empty?

    "outdated: #{newer.map { |r| "#{r.slug} at #{r.newest_issue}" }.join(', ')}"
  end

  def register_index(root)
    catalog = Ituob::Support::Yaml.safe_load_file(File.join(root, 'catalogs', 'registers.yaml'))
    catalog.fetch('registers').each_with_object({}) do |entry, index|
      next unless entry['seed_path']

      slug = File.basename(entry['seed_path'])
      seed = entry['seed_issue']&.to_i || 0
      index[slug] = Register.new(
        slug: entry['slug'], seed_path: entry['seed_path'], seed_issue: seed,
        newest_issue: newest_issue(File.join(root, entry['seed_path']), seed)
      )
    end
  end

  # The newest OB issue the replay would read: the loader's own file selection
  # (.yaml/.yml with a `type`, issue from the content, nothing before the seed).
  def newest_issue(seed_dir, seed)
    source = Ituob::Registers::DirectoryChangeSource.new(
      register_id: File.basename(seed_dir), seed_path: seed_dir, seed_issue: seed, key_field: 'code'
    )
    ([seed] + source.each_sorted.filter_map(&:ob_issue_no)).max
  end

  def render(rows)
    out = []
    out << '= Service Publication PDF coverage matrix'
    out << ':!sectnums:'
    out << ''
    out << '// GENERATED by scripts/build_pdf_coverage_matrix.rb. Do not edit by hand.'
    out << ''
    out << summary(rows)
    out << ''
    out << '== Matrix'
    out << ''
    out << '[cols="2,1,1,1,1,1,3,3,1",options="header"]'
    out << '|==='
    out << '| Publication | Edition | Lang | As-of OB issue | Header docnumber | Published | Registers (slug) | Against register state | Data path'
    rows.each { |r| out << row_cells(r) }
    out << '|==='
    out << ''
    out.join("\n")
  end

  def row_cells(row)
    regs = row.registers.map(&:slug)
    regs += row.unmapped.map { |u| "#{u} (no register)" }
    [
      row.standard, row.year, row.language, issue_cell(row),
      row.docnumber.to_s, row.published.to_s, regs.join(', '), row.flag, row.data_path
    ].map { |c| c.to_s.gsub('|', '{vbar}') }.join(' | ').prepend('| ')
  end

  def issue_cell(row)
    return '' unless row.issue
    return row.issue.to_s if row.datasets.map(&:last).uniq.size == 1

    "#{row.issue} (max of #{row.datasets.map { |s, i| "#{s}=#{i}" }.join(', ')})"
  end

  def summary(rows)
    pubs = rows.map { |r| [r.standard, r.year] }.uniq
    langs = rows.group_by(&:language).transform_values(&:size).sort.map { |l, n| "#{l}: #{n}" }
    flags = rows.group_by { |r| r.flag.split(':').first.split(' (').first }
                .transform_values(&:size).sort.map { |f, n| "#{f}: #{n}" }
    [
      '== Summary', '',
      "* Publications: #{pubs.size}",
      "* Publication x language rows: #{rows.size}",
      "* Rows by language: #{langs.join(', ')}",
      "* Rows by register state: #{flags.join(', ')}",
      "* Rows by data path: #{rows.group_by(&:data_path).sort.map { |name, group| "#{name}: #{group.size}" }.join(', ')}",
      "* Rows whose header `:docnumber:` differs from the as-of issue: #{rows.count { |r| r.docnumber.to_s != r.issue.to_s }}",
      '',
      'The as-of OB issue is the highest leading number among the dataset directories',
      'named in a document data block (for example `1114-E.164D`), or the explicit',
      '`as_of` argument of its provider source. Provider publication queries read',
      'the complete typed seed edition, preserving repeated register keys. When',
      'the datasets differ, every dataset issue is listed. The header `:docnumber:`',
      'is not used for it: it is often not an issue number or is stale.',
      '',
      'Register state is the newest OB issue the change loader would replay from',
      '`datasets/<seed>/changes/` (or the seed issue when there is none), read',
      'from `catalogs/registers.yaml`. A row is outdated when the issue of the dataset',
      'it reads for a register is older than that. Datasets with no register in the',
      'catalog are listed as "no register" and are not compared.',
      '',
      'Data path is `provider` when all data blocks query the provider, `mixed`',
      'when provider and file injection blocks coexist, or `yaml2text` otherwise.'
    ].join("\n")
  end

  def main(argv)
    root = File.expand_path('..', __dir__)
    out = nil
    OptionParser.new do |o|
      o.on('--root DIR') { |v| root = File.expand_path(v) }
      o.on('--out FILE') { |v| out = v }
    end.parse!(argv)
    File.write(out || File.join(root, OUT_PATH), render(rows(root)), encoding: 'UTF-8') if false
    File.write(out || File.join(root, OUT_PATH), render(rows(root)))
  end
end

PdfCoverageMatrix.main(ARGV) if $PROGRAM_NAME == __FILE__
