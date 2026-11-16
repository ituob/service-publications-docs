#!/usr/bin/env ruby
# frozen_string_literal: true
#
# ob_print_to_patch_coverage.rb
#
# Card 100-05 (ituob/ituob.github.io#100): account for every printed
# amendment line of every Operational Bulletin issue (669 .. latest).
#
# A "printed line" is one visual line of itu-ob-data/issues/N/amendments.yaml:
# a paragraph or heading (split at hard breaks) or one table row. Each line
# is classified as exactly one of
#
#   mapped_structured   every token of the line is carried by ONE structured
#                       register patch (ob-issues/N/<slug>/NNN-ACT.yaml or
#                       datasets/*/changes/NNNN-*.yaml) of the message's register
#   mapped_split        every token is carried by the register's structured
#                       patches of that issue together, no single file has all
#   mapped_text         carried by the register's verbatim text.yaml only
#   mapped_other        carried by a patch of ANOTHER register in the same issue
#   mapped_values_only  as mapped_structured, except the printed field labels
#                       (Tel, Fax, E-mail, the leading page marker "P") which
#                       are field names in the patch, not stored text
#   excluded            matches a named exclusion rule (see EXCLUSION_RULES)
#   unmapped            none of the above; listed with issue + source line
#
# Matching is token containment (case, accents and punctuation folded, dates
# expanded), not row alignment: it proves the printed words reached a patch,
# not that they sit in the right field. Exclusions are only consulted for lines
# that did not map, so a rule never hides a mapped line.
#
# Re-runnable and deterministic (no timestamps). Read-only on itu-ob-data.
#
#   ruby scripts/ob_print_to_patch_coverage.rb
#
# Environment overrides (used by the spec):
#   ITU_OB_DATA_ROOT   dir holding issues/<N>/amendments.yaml
#   OB_ISSUES_ROOT     dir holding <N>/<slug>/*.yaml
#   DATASETS_ROOT      dir holding <seed>/changes/*.yaml
#   REGISTERS_CATALOG  catalogs/registers.yaml
#   COVERAGE_OUT_DIR   output directory (default scripts/output)
#   COVERAGE_MIN_ISSUE lowest issue number (default 669)

require 'yaml'
require 'date'
require 'set'
require 'fileutils'
require 'open3'

module PrintToPatchCoverage
  REPO_ROOT = File.expand_path('..', __dir__)

  # Same table as scripts/build_ob_issues.rb (guarded by a spec).
  SLUG_BY_PUBLICATION = {
    'E118_IIN' => 'e118-iin', 'DP' => 'dp', 'E164_ACN' => 'e164-acn',
    'E164_CC' => 'e164-cc', 'E212_ICC' => 'e212-icc', 'E212_MNC' => 'e212-mnc',
    'E218_TRCC' => 'e218-trcc', 'F32_TDI' => 'f32-tdi', 'F400_ADMD' => 'f400-admd',
    'M1400_ICC' => 'm1400-icc', 'Q708_ISPC' => 'q708-ispc', 'Q708_SANC' => 'q708-sanc',
    'T35_NA' => 't35-na', 'X121_DNIC' => 'x121-dnic', 'RR.25.1' => 'rr251',
    'BUREAUFAX' => 'bureaufax',
    'List of Coast Stations and Special Service Stations' => 'coast-stations',
    'R_SP_LM.V' => 'list-v', 'R_SP_LN.VIII' => 'list-viii', 'NNP' => 'nnp'
  }.freeze

  ACTION_FILE = /\A\d+-[A-Z][A-Z0-9]*\.yaml\z/

  MONTHS = %w[january february march april may june july august september
              october november december].freeze

  Line = Struct.new(:issue, :msg_index, :publication, :slug, :text, :source_line,
                    :tokens, keyword_init: true)
  Patch = Struct.new(:path, :layer, :kind, :tokens, keyword_init: true)

  # Normalized (folded, tokens joined by one space) titles of table columns.
  HEADER_CELLS = Set.new([
    'country geographical area', 'country', 'country or area iso code', 'country or geographical area',
    'country geographical area or global service', 'company name address', 'carrier code',
    'company code', 'company code carrier code', 'issuer identifier number', 'contact',
    'effective date of usage', 'effective date of cancellation', 'date of cancellation',
    'ispc', 'dec', 'unique name of the signalling point', 'name of the signalling point operator',
    'country code cc', 'country code', 'mcc mnc', 'mcc mnc operator network', 'operator network',
    'name of operator network', 'name of network operator', 'name of operator', 'operator', 'mcc',
    'applicant', 'network', 'country code and identification code', 'status',
    'e 164 country code', 'mobile telephone numbers first digits after country code',
    'international prefix', 'national prefix', 'national significant number', 'utc dst', 'note',
    'admd name', 'service name s', 'helpdesk', 'autoanswer', 'contact address', 'mt', 'ipm', 'other',
    'country geographical area network administration roa',
    'destination indicator di first 2 letters telegram network code', 'name of telegraph office',
    'di assigned to telegraph office', 'network code', 'office code', 'pais zona geografica', 'country on aera iso code', 'company code',
    'country or area iso code code de la societe', 'code de la societe',
    'destination indicator di first 2 letters telegram network code', 'country geographical area ispc dec',
    'country geographical area network administration roa'
  ]).freeze

  # Named exclusion rules, consulted only for lines that did not map.
  # Each: id, reason, matcher(normalized_text, tokens). Filled from the
  # measured unmapped population; see EXCLUSION_RULES below.
  Rule = Struct.new(:id, :reason, :match, keyword_init: true)

  EXCLUSION_RULES = [
    Rule.new(
      id: 'column_header',
      reason: 'table column titles ("Country/ geographical area | Company Name/Address ..."): labels of the ' \
              'register fields, repeated on every printed table; the field names live in the register schema',
      match: lambda { |_text, _tokens, cells|
        cells.any? && cells.all? { |c| c.empty? || HEADER_CELLS.include?(c) || (cells.size >= 3 && c.match?(/\A\d{1,2}[a-z]?\z/)) }
      }
    ),
    Rule.new(
      id: 'ordering_directive',
      reason: 'printed insertion-order heading ("Numerical order ADD", "Alphabetical order ADD"); registers are ' \
              'keyed, not ordered, so the directive has no field in a patch',
      match: ->(_text, tokens, _cells) { tokens.to_a.sort.join(' ').match?(/\A(add|alphabetical|numerical|order)( (add|alphabetical|numerical|order))*\z/) && tokens.size <= 3 }
    ),
    Rule.new(
      id: 'glossary_legend',
      reason: 'trilingual legend of a column abbreviation ("MNC : Mobile Network Code / Code de reseau mobile / ' \
              'Indicativo de red ..."), repeated boilerplate; the abbreviation is a register field name',
      match: ->(text, _tokens, _cells) { text.match?(%r{\A[[:space:]*_]*[A-Z]{2,6}[[:space:]]*:[[:space:]]*\p{L}.* / }) }
    ),
    Rule.new(
      id: 'page_cross_reference',
      reason: 'footnote pointing at another printed page of the Bulletin ("See the present ITU Operational ' \
              'Bulletin No. N, page 5"); a layout reference, not register content',
      match: ->(text, _tokens, _cells) { text.match?(/\A[[:space:]*]*See (the present )?(ITU )?(Operational Bulletin|page)/i) }
    ),
    Rule.new(
      id: 'amendment_banner',
      reason: 'banner restating message metadata: "(Amendment No. N)" / "(Position on D Month YYYY)"; the date is ' \
              "the message's position_on, the number is the Bulletin amendment series, neither is a register field",
      match: ->(text, _tokens, _cells) { text.match?(/\A[[:space:]]*\((Amendment No\.? ?\d+|Position on [^)]*)\)[[:space:]]*\z/i) }
    ),
    Rule.new(
      id: 'form_label_only',
      reason: 'form field label printed with no value ("Department:"); the field name is in the register schema',
      match: ->(text, _tokens, _cells) { text.match?(/\A[[:space:]]*\p{L}[\p{L} \/().,'-]{0,50}:[[:space:]]*(\|[[:space:]|]*)?\z/) }
    ),
    Rule.new(
      id: 'shared_mcc_intro',
      reason: 'introductory sentence of the shared-country-code (882/883) identification-code table; the table ' \
              'rows carry the data',
      match: ->(_text, tokens, _cells) { tokens.include?('shared') && tokens.include?('associated') && tokens.include?('networks') }
    )
  ].freeze

  # ---- tokens --------------------------------------------------------

  module Tok
    module_function

    def fold(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{M}/, '').downcase
    end

    def of(str)
      fold(str).scan(/[[:alnum:]]+/)
    end

    # Add the unpadded form of a numeric token so "03" meets "3".
    def with_unpadded(tokens)
      tokens.flat_map { |t| t =~ /\A0+\d+\z/ ? [t, t.sub(/\A0+/, '')] : [t] }
    end

    def date_tokens(year, month, day)
      [year.to_s, format('%02d', month), month.to_s, format('%02d', day), day.to_s,
       MONTHS[month - 1], MONTHS[month - 1][0, 3]]
    end

    def of_patch_value(str)
      toks = of(str)
      str.to_s.scan(/(\d{4})-(\d{2})-(\d{2})/) do |y, m, d|
        toks.concat(date_tokens(y, m.to_i, d.to_i))
      end
      with_unpadded(toks)
    end
  end

  # ---- YAML with line numbers ---------------------------------------

  # Parses to plain Hash/Array/String. Every Hash gets '__line' (1-based
  # line of the mapping); a 'text' scalar also records '__text_line'.
  module Ast
    module_function

    def load_file(path)
      stream = Psych.parse_stream(File.read(path), filename: path)
      root = stream.children.first&.children&.first
      root ? conv(root) : nil
    end

    def conv(node)
      case node
      when Psych::Nodes::Mapping
        h = { '__line' => node.start_line + 1 }
        node.children.each_slice(2) do |k, v|
          key = k.is_a?(Psych::Nodes::Scalar) ? k.value : nil
          next if key.nil?

          h['__text_line'] = v.start_line + 1 if key == 'text'
          h[key] = conv(v)
        end
        h
      when Psych::Nodes::Sequence then node.children.map { |c| conv(c) }
      when Psych::Nodes::Scalar then node.value
      end
    end
  end

  # ---- printed lines -------------------------------------------------

  module Extract
    module_function

    # -> [[text, source_line], ...]  (only lines with an alphanumeric char)
    def lines(contents)
      case contents
      when String then contents.split("\n").each_with_index.map { |t, i| [t, i + 1] }
      when Hash then walk(contents, [])
      else []
      end.select { |text, _| text =~ /[[:alnum:]]/ }
    end

    def walk(node, out)
      return out unless node.is_a?(Hash)

      case node['type']
      when 'paragraph', 'heading' then inline_lines(node, out)
      when 'table' then table_rows(node, out)
      else Array(node['content']).each { |c| walk(c, out) }
      end
      out
    end

    def inline_lines(node, out)
      buf = +''
      first = nil
      flush = lambda do
        out << [buf.strip, first || node['__line']] unless buf.strip.empty?
        buf = +''
        first = nil
      end
      add = lambda do |text, ln|
        first ||= ln
        buf << text
      end
      collect_inline(node, add, flush)
      flush.call
    end

    def collect_inline(node, add, flush)
      Array(node['content']).each do |c|
        next unless c.is_a?(Hash)

        case c['type']
        when 'text' then add.call(c['text'].to_s, c['__text_line'] || c['__line'])
        when 'hard_break' then flush.call
        else collect_inline(c, add, flush)
        end
      end
    end

    def table_rows(table, out)
      Array(table['content']).each do |row|
        next unless row.is_a?(Hash)

        if row['type'] == 'table_row'
          cells = Array(row['content']).map { |cell| cell_text(cell) }
          line = first_line(row)
          out << [cells.join(' | '), line] if cells.join =~ /[[:alnum:]]/
        else
          walk(row, out)
        end
      end
    end

    def cell_text(cell)
      parts = []
      each_text(cell) { |t| parts << t }
      parts.join(' ').gsub(/\s+/, ' ').strip
    end

    def each_text(node, &blk)
      return unless node.is_a?(Hash)

      blk.call(node['text'].to_s) if node['type'] == 'text'
      Array(node['content']).each { |c| each_text(c, &blk) }
    end

    def first_line(node)
      return node['__text_line'] if node['__text_line']

      Array(node['content']).each do |c|
        l = c.is_a?(Hash) && first_line(c)
        return l if l
      end
      node['__line']
    end
  end

  # ---- patches -------------------------------------------------------

  class Patches
    attr_reader :slug_by_seed, :orphan_change_dirs

    def initialize(ob_issues_root:, datasets_root:, catalog_path:)
      @ob_issues_root = ob_issues_root
      @datasets_root = datasets_root
      @slugs_by_dataset_dir = {}
      load_catalog(catalog_path)
      @change_index = index_changes
      @cache = {}
    end

    # -> { slug => [Patch] } for one issue (ob-issues + datasets changes)
    def for_issue(issue)
      @cache[issue] ||= begin
        by_slug = Hash.new { |h, k| h[k] = [] }
        issue_dir = File.join(@ob_issues_root, issue.to_s)
        Dir.glob(File.join(issue_dir, '*', '*.yaml')).sort.each do |path|
          slug = File.basename(File.dirname(path))
          by_slug[slug] << ob_issue_patch(path)
        end
        (@change_index[issue] || []).each do |dataset_dir, path|
          slug = @slugs_by_dataset_dir[dataset_dir]
          slug ||= "(unregistered:#{dataset_dir})"
          by_slug[slug] << change_patch(path)
        end
        by_slug
      end
    end

    def rel(path)
      path.delete_prefix("#{File.dirname(@ob_issues_root)}/")
    end

    def unregistered
      @change_index.values.flatten(1).map(&:first).uniq.reject { |d| @slugs_by_dataset_dir.key?(d) }
    end

    private

    def load_catalog(path)
      reg = YAML.safe_load(File.read(path), aliases: true)['registers']
      Array(reg).each do |r|
        next unless r['seed_path']

        dir = r['seed_path'].sub(%r{\Adatasets/}, '')
        @slugs_by_dataset_dir[dir] = r['source_slug'] || r['slug']
      end
    end

    def index_changes
      idx = Hash.new { |h, k| h[k] = [] }
      Dir.glob(File.join(@datasets_root, '*', 'changes', '*.yaml')).sort.each do |path|
        issue = File.basename(path)[/\A(\d+)-/, 1]
        next unless issue

        dir = path.split(File::SEPARATOR)[-3]
        idx[issue.to_i] << [dir, path]
      end
      idx
    end

    def ob_issue_patch(path)
      kind = File.basename(path) == 'text.yaml' ? :text : :structured
      Patch.new(path: path, layer: :ob_issues, kind: kind, tokens: tokens_of_file(path))
    end

    def change_patch(path)
      Patch.new(path: path, layer: :changes, kind: :structured, tokens: tokens_of_file(path))
    end

    def tokens_of_file(path)
      data = YAML.safe_load(File.read(path), aliases: true,
                                              permitted_classes: [Date, Time, DateTime, Symbol])
      set = Set.new
      if File.basename(path) == 'text.yaml' && data.is_a?(Hash) && data['contents'].is_a?(Hash)
        # Verbatim ProseMirror: tokenise per printed line, the way the source
        # is, so "CS" + "3" in two text nodes is the token "cs3" on both sides.
        Extract.lines(data['contents']).each { |text, _| set.merge(Tok.with_unpadded(Tok.of(text))) }
      end
      collect(data, set)
      set
    rescue StandardError => e
      warn "coverage: cannot read #{path}: #{e.class}: #{e.message}"
      Set.new
    end

    def collect(node, set)
      case node
      when Hash then node.each_value { |v| collect(v, set) }
      when Array then node.each { |v| collect(v, set) }
      when Date, Time
        set.merge(Tok.date_tokens(node.year, node.month, node.day))
      when String then set.merge(Tok.of_patch_value(node))
      when Integer, Float then set.merge(Tok.of_patch_value(node.to_s))
      end
    end
  end

  # ---- classification ------------------------------------------------

  Result = Struct.new(:line, :status, :detail, :patch, :missing, keyword_init: true)

  class Classifier
    def initialize(patches)
      @patches = patches
    end

    def classify(line, collision:)
      tokens = line.tokens
      by_slug = @patches.for_issue(line.issue)
      own = by_slug[line.slug] || []
      structured = own.select { |p| p.kind == :structured }
      texts = own.select { |p| p.kind == :text }

      if (hit = pick(structured, tokens))
        return Result.new(line: line, status: :mapped_structured, patch: hit)
      end
      if !structured.empty? && union_covers?(structured, tokens)
        return Result.new(line: line, status: :mapped_split, patch: structured.first)
      end
      if (hit = pick(texts, tokens))
        return Result.new(line: line, status: :mapped_text, patch: hit)
      end

      other = by_slug.reject { |s, _| s == line.slug }.values.flatten
      if (hit = pick(other.select { |p| p.kind == :structured }, tokens))
        return Result.new(line: line, status: :mapped_other, patch: hit,
                          detail: by_slug.key(by_slug.values.find { |a| a.include?(hit) }))
      end

      stripped = strip_labels(line)
      if stripped.size < tokens.size && !stripped.empty?
        hit = pick(structured, stripped) ||
              (union_covers?(structured, stripped) ? structured.first : nil)
        return Result.new(line: line, status: :mapped_values_only, patch: hit) if hit
      end

      cells = (line.text.include?(' | ') ? line.text.split(' | ') : line.text.split(/[[:space:]]{2,}/))
              .map { |c| Tok.of(c).join(' ') }
      if (rule = EXCLUSION_RULES.find { |r| r.match.call(line.text, tokens, cells) })
        return Result.new(line: line, status: :excluded, detail: rule.id)
      end

      all_own = own.map(&:tokens).reduce(Set.new, :|)
      missing = tokens.reject { |t| all_own.include?(t) }
      Result.new(line: line, status: :unmapped, detail: cause_of(line, own, collision, missing),
                 missing: missing)
    end

    # Deterministic cause tag for an unmapped line (first match wins).
    def cause_of(line, own, collision, missing)
      text = line.text
      if own.empty? then 'no_patch_for_register'
      elsif collision then 'same_register_repeated_in_issue'
      elsif text.include?('@') && missing.any? { |t| Tok.of(text[/\S+@\S+/].to_s).include?(t) }
        'email_address_not_in_patch'
      elsif text.match?(%r{\A[[:space:]]*\p{L}[^|]*(\(.*\)|/)[[:space:]]*(?!(ADD|SUP|REP|LIR)\b)[A-Z]{3}[[:space:]]*(ADD|SUP|REP|LIR)?[[:space:]]*\z})
        'country_heading_long_name_and_iso_not_in_patch'
      elsif text.match?(/\A[[:space:]]*P[[:space:]]*\d+/) && (missing - %w[add sup rep lir to p]).empty?
        'page_marker_action_not_in_patch'
      elsif line.slug == 'coast-stations' && text.match?(/\A[[:space:]*]*(CS\d+|See note CS\d+|Notes[[:space:]]+CS)/i)
        'coast_station_note_not_in_patch'
      elsif line.slug == 'list-viii' && text.match?(/\A[[:space:]]*\d+\.[[:space:]]/)
        'list_viii_numbered_item_not_in_patch'
      elsif (missing - LABEL_TOKENS.to_a - %w[e]).all? { |t| t.match?(/\A\d+\z/) } && (missing - LABEL_TOKENS.to_a - %w[e]).any?
        'only_numeric_tokens_missing_value_or_number_format'
      elsif missing.size == line.tokens.size then 'no_token_in_register_patches'
      else 'token_missing_from_register_patches'
      end
    end

    private

    # The printed field labels that a patch stores as field names, plus the
    # leading page marker ("P 24 Gibraltar SUP": P = the Bulletin page letter).
    LABEL_TOKENS = Set.new(%w[tel fax mail email]).freeze

    def strip_labels(line)
      text = line.text.sub(/(?<![[:alnum:]])[A-Z][[:space:]]+(?=\d)/, '')
      text = text.sub(/\A[^|]*:[[:space:]]*\|/, '')            # "Label: | value" form row
      text = text.sub(/\A[^|?]*\?[[:space:]]+(?=\S+\z)/, '')  # "Label? YES" form row
      toks = Tok.with_unpadded(Tok.of(text))
      drop_e = toks.include?('mail')
      Set.new(toks.reject { |t| LABEL_TOKENS.include?(t) || (drop_e && t == 'e') })
    end

    def pick(patches, tokens)
      patches.find { |p| p.layer == :ob_issues && p.tokens.superset?(tokens) } ||
        patches.find { |p| p.tokens.superset?(tokens) }
    end

    def union_covers?(patches, tokens)
      all = patches.map(&:tokens).reduce(Set.new, :|)
      all.superset?(tokens)
    end
  end

  # ---- driver ----------------------------------------------------------

  class Run
    attr_reader :results, :issues, :non_text, :warnings, :patches

    def initialize(env = ENV)
      @data_root = env.fetch('ITU_OB_DATA_ROOT') { File.join(REPO_ROOT, 'itu-ob-data', 'issues') }
      @ob_root = env.fetch('OB_ISSUES_ROOT') { File.join(REPO_ROOT, 'ob-issues') }
      @datasets_root = env.fetch('DATASETS_ROOT') { File.join(REPO_ROOT, 'datasets') }
      @catalog = env.fetch('REGISTERS_CATALOG') { File.join(REPO_ROOT, 'catalogs', 'registers.yaml') }
      @min_issue = Integer(env.fetch('COVERAGE_MIN_ISSUE', '669'), 10)
      @results = []
      @warnings = []
      @issues = []
      @patches = Patches.new(ob_issues_root: @ob_root, datasets_root: @datasets_root,
                             catalog_path: @catalog)
      @classifier = Classifier.new(@patches)
      @messages_per_slug = Hash.new(0)
    end

    def data_ids
      Dir.children(@data_root).grep(/\A\d+\z/).map(&:to_i).select { |i| i >= @min_issue }.sort
    end

    def run
      data_ids.each { |id| process_issue(id) }
      self
    end

    def source_path(issue) = File.join(@data_root, issue.to_s, 'amendments.yaml')

    private

    def process_issue(issue)
      path = source_path(issue)
      return unless File.file?(path)

      @issues << issue
      doc = Ast.load_file(path)
      messages = doc.is_a?(Hash) ? Array(doc['messages']) : []
      amendments = messages.each_with_index.select { |m, _| m.is_a?(Hash) && m['type'] == 'amendment' }
      per_slug = Hash.new(0)
      amendments.each { |m, _| per_slug[slug_for(m)] += 1 if m.dig('target', 'publication') }

      amendments.each do |msg, idx|
        pub = msg.dig('target', 'publication')
        next unless pub

        slug = slug_for(msg)
        contents = msg.dig('contents', 'en')
        unless contents
          @warnings << "#{issue} message #{idx + 1} (#{pub}): no en contents"
          next
        end
        Extract.lines(contents).each do |text, src_line|
          tokens = Set.new(Tok.with_unpadded(Tok.of(text)))
          line = Line.new(issue: issue, msg_index: idx + 1, publication: pub, slug: slug,
                          text: text, source_line: src_line, tokens: tokens)
          @results << @classifier.classify(line, collision: per_slug[slug] > 1)
        end
      end
    end

    def slug_for(msg)
      pub = msg.dig('target', 'publication')
      SLUG_BY_PUBLICATION.fetch(pub) { pub.downcase.gsub(/[^a-z0-9.]+/, '-') }
    end
  end

  # ---- report ----------------------------------------------------------

  STATUSES = %i[mapped_structured mapped_split mapped_text mapped_other mapped_values_only excluded unmapped].freeze

  class Report
    def initialize(run, data_sha)
      @run = run
      @data_sha = data_sha
    end

    def totals(results)
      STATUSES.to_h { |s| [s, results.count { |r| r.status == s }] }.merge(total: results.size)
    end

    def mapped_count(t) = t[:mapped_structured] + t[:mapped_split] + t[:mapped_text] + t[:mapped_other] + t[:mapped_values_only]

    def markdown
      results = @run.results
      t = totals(results)
      out = +"# Print-to-patch coverage (card 100-05)\n\n"
      out << "Generated by `scripts/ob_print_to_patch_coverage.rb`; re-run to refresh. No timestamps.\n\n"
      out << "* itu-ob-data: `#{@data_sha}`\n"
      out << "* issues: #{@run.issues.first}..#{@run.issues.last} (#{@run.issues.size} issues with amendments.yaml)\n"
      missing = (@run.issues.first..@run.issues.last).to_a - @run.issues
      out << "* issue numbers in that range with no amendments.yaml in itu-ob-data (nothing printed to account for): " \
             "#{missing.empty? ? 'none' : "#{missing.size} (#{ranges(missing)})"}\n"
      out << "* printed line: a paragraph/heading (split at hard breaks) or table row of an `amendment` " \
             "message with at least one letter or digit\n\n"
      out << "## Totals\n\n"
      out << summary_table('all issues', t)
      out << "\n## Per register\n\n"
      out << group_table(results) { |r| r.line.slug }
      out << "\n## Exclusion rules\n\n"
      out << exclusion_table(results)
      out << "\n## Unmapped by cause\n\n"
      out << cause_table(results)
      out << "\n## Unmapped by register\n\n"
      out << unmapped_by_register(results)
      out << "\n## Unmapped by issue (top 40)\n\n"
      out << unmapped_by_issue(results)
      out << "\n## Per issue\n\n"
      out << group_table(results) { |r| r.line.issue }
      unless @run.warnings.empty?
        out << "\n## Warnings\n\n"
        @run.warnings.each { |w| out << "* #{w}\n" }
      end
      out
    end

    def ranges(nums)
      nums.chunk_while { |a, b| b == a + 1 }.map { |c| c.size > 1 ? "#{c.first}-#{c.last}" : c.first.to_s }.join(', ')
    end

    def unmapped_tsv
      rows = @run.results.select { |r| r.status == :unmapped }
      out = +"issue\tsource\tmessage\tregister\tcause\tmissing_tokens\ttext\n"
      rows.each do |r|
        l = r.line
        out << [l.issue, "issues/#{l.issue}/amendments.yaml:#{l.source_line}", l.msg_index, l.slug,
                r.detail, r.missing.join(' '), l.text.gsub(/[\t\n]/, ' ')].join("\t") << "\n"
      end
      out
    end

    def excluded_tsv
      out = +"issue\tsource\tregister\trule\ttext\n"
      @run.results.select { |r| r.status == :excluded }.each do |r|
        l = r.line
        out << [l.issue, "issues/#{l.issue}/amendments.yaml:#{l.source_line}", l.slug, r.detail,
                l.text.gsub(/[\t\n]/, ' ')].join("\t") << "\n"
      end
      out
    end

    private

    def pct(num, den) = den.zero? ? '-' : format('%.2f%%', 100.0 * num / den)

    def summary_table(label, t)
      mapped = mapped_count(t)
      out = +"| #{label} | printed | mapped | of which structured / split / text / other / values-only | excluded | unmapped | mapped % |\n"
      out << "|---|---|---|---|---|---|---|\n"
      out << "| total | #{t[:total]} | #{mapped} | #{t[:mapped_structured]} / #{t[:mapped_split]} / " \
             "#{t[:mapped_text]} / #{t[:mapped_other]} / #{t[:mapped_values_only]} | #{t[:excluded]} | #{t[:unmapped]} | " \
             "#{pct(mapped, t[:total])} |\n"
    end

    def group_table(results)
      groups = results.group_by { |r| yield r }
      out = +"| key | printed | mapped | structured | split | text | other | values-only | excluded | unmapped |\n"
      out << "|---|---|---|---|---|---|---|---|---|---|\n"
      groups.sort_by { |k, _| k.is_a?(Integer) ? k : k.to_s }.each do |k, rs|
        t = totals(rs)
        out << "| #{k} | #{t[:total]} | #{mapped_count(t)} | #{t[:mapped_structured]} | #{t[:mapped_split]} | " \
               "#{t[:mapped_text]} | #{t[:mapped_other]} | #{t[:mapped_values_only]} | #{t[:excluded]} | #{t[:unmapped]} |\n"
      end
      out
    end

    def exclusion_table(results)
      ex = results.select { |r| r.status == :excluded }.group_by(&:detail)
      out = +"| rule | lines | reason | example (issue:line text) |\n|---|---|---|---|\n"
      EXCLUSION_RULES.each do |rule|
        rs = ex[rule.id] || []
        eg = rs.first
        sample = eg ? "#{eg.line.issue}:#{eg.line.source_line} `#{eg.line.text[0, 80].gsub('|', '/')}`" : '-'
        out << "| #{rule.id} | #{rs.size} | #{rule.reason} | #{sample} |\n"
      end
      out << "| (none defined) | 0 | - | - |\n" if EXCLUSION_RULES.empty?
      out
    end

    def cause_table(results)
      rs = results.select { |r| r.status == :unmapped }.group_by(&:detail)
      out = +"| cause | lines | example (issue:line register text) |\n|---|---|---|\n"
      rs.sort_by { |_, v| -v.size }.each do |cause, list|
        eg = list.first.line
        out << "| #{cause} | #{list.size} | #{eg.issue}:#{eg.source_line} #{eg.slug} " \
               "`#{eg.text[0, 80].gsub('|', '/')}` |\n"
      end
      out
    end

    def unmapped_by_register(results)
      rs = results.select { |r| r.status == :unmapped }.group_by { |r| r.line.slug }
      out = +"| register | unmapped | issues affected |\n|---|---|---|\n"
      rs.sort_by { |_, v| -v.size }.each do |slug, list|
        out << "| #{slug} | #{list.size} | #{list.map { |r| r.line.issue }.uniq.size} |\n"
      end
      out
    end

    def unmapped_by_issue(results)
      rs = results.select { |r| r.status == :unmapped }.group_by { |r| r.line.issue }
      out = +"| issue | unmapped |\n|---|---|\n"
      rs.sort_by { |i, v| [-v.size, i] }.first(40).each { |i, list| out << "| #{i} | #{list.size} |\n" }
      out
    end
  end

  def self.data_sha(root)
    dir = File.dirname(root)
    sha, st = Open3.capture2('git', 'rev-parse', '--short=8', 'HEAD', chdir: dir, err: File::NULL)
    st.success? ? sha.strip : 'unknown'
  rescue StandardError
    'unknown'
  end

  def self.main(env = ENV)
    run = Run.new(env).run
    sha = data_sha(env.fetch('ITU_OB_DATA_ROOT') { File.join(REPO_ROOT, 'itu-ob-data', 'issues') })
    report = Report.new(run, sha)
    out_dir = env.fetch('COVERAGE_OUT_DIR') { File.join(REPO_ROOT, 'scripts', 'output') }
    FileUtils.mkdir_p(out_dir)
    File.write(File.join(out_dir, '100-05-print-to-patch-coverage.md'), report.markdown)
    File.write(File.join(out_dir, '100-05-unmapped-lines.tsv'), report.unmapped_tsv)
    File.write(File.join(out_dir, '100-05-excluded-lines.tsv'), report.excluded_tsv)
    t = report.totals(run.results)
    puts "printed=#{t[:total]} mapped=#{report.mapped_count(t)} excluded=#{t[:excluded]} unmapped=#{t[:unmapped]} " \
         "(structured=#{t[:mapped_structured]} split=#{t[:mapped_split]} text=#{t[:mapped_text]} " \
         "other=#{t[:mapped_other]} values_only=#{t[:mapped_values_only]})"
    t
  end
end

PrintToPatchCoverage.main if $PROGRAM_NAME == __FILE__
