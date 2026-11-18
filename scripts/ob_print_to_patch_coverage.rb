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
  Patch = Struct.new(:path, :layer, :kind, :tokens, :numbers, keyword_init: true)

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

  ADDITIONAL_HEADER_CELLS = Set.new([
    'applicant network', 'auto answer', 'company name address carrier code', 'contact name',
    'country b where the mcc mnc is to be used extra territorially',
    'country or geographical area', 'operators name',
    'country code and trial identification code', 'country geographical area global network',
    'country geographical area mcc mnc', 'country geographical code', 'country name address',
    'country or area iso code company code', 'country or area iso code company name address',
    'date of assigment', 'date of registration', 'date of usage', 'date of withdrawal',
    'di assigned to telegraph office third and fourth letters office code',
    'effective date of assignment', 'effective date of registration', 'effective date of withdrawal',
    'issuer identification number', 'mobile subscription identification number', 'msin',
    'msin range to be used', 'msin range to be used in country a', 'msin range to be used in country b',
    'name of assignee', 'name of operator s countries a and b', 'network administration roa',
    'nom de reseau operateur', 'pais o zona geografica', 'pays ou zone geographique',
    'pays zone geographique', 'reclamation date'
  ]).freeze
  NUMBERED_COUNTRY_CODE_HEADER = /\Acountry \| admd name \| country code 1 \| service name s \| helpdesk \| (?:auto ?answer \| )?contact address\z/

  NUMBERED_HEADER_ROWS = Set.new([
    '1 | 2 | 3 | 4 | 5', '1 | 2 | 3 | 4 | 5 | 6',
    '1 | 2 | 3 | 4 | 5a | 5b | 6', '1 | 2 | 3 | 4 | 5a | 5b | 6 | 7',
    '1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9'
  ]).freeze

  LIST_VIII_ITEMS = {
    2 => 'Geographical coordinates', 3 => 'Hours of service', 4 => 'Information on antennas in use',
    5 => 'Range of azimuth and elevation angles',
    6 => 'Maximum attainable accuracy in determining orbital positions(?: of space stations)?', 7 => 'Information on system polarization',
    8 => 'System noise temperature', 9 => 'Ranges of frequencies with the maximum attainable accuracy(?: of frequency measurement for each frequency range)?',
    10 => 'Ranges of frequencies in which field strength(?: or power flux-density measurements can be performed)?', 11 => 'Minimum value of measurable field strength(?: or power flux-density with indication of attainable accuracy of measurement)?',
    12 => 'Information available for bandwidth(?: measurements)?', 13 => 'Information available for spectrum occupancy(?: measurements)?',
    14 => 'Information available for orbit occupancy(?: measurements)?'
  }.freeze
  LIST_VIII_LABEL = Regexp.new(
    '\A[[:space:]]*(?:' + LIST_VIII_ITEMS.map { |n, t| "#{n}\\.[[:space:]]+#{t}" }.join('|') + ')(?=[[:space:]:]|\z)'
  )
  LIST_VIII_LABEL_ONLY = Regexp.new(LIST_VIII_LABEL.source + '[[:space:]]*:?[[:space:]]*\z')

  # Remove only fixed layout/directive text; names and codes still need patches.
  module PageHeading
    ACTION = /\b(?:ADD|SUP|LIR|REP)(?:1\)?)?\b/
    module_function

    def values(text)
      return text unless text.match?(ACTION)

      text.gsub(/\((?:delete|read)\)/i, ' ')
          .gsub(/\ball information(?:s)? by[[:space:]]*:?/i, ' ')
          .gsub(/\b(?:by )?(?:Numeric(?:al)?|Alphabetical) order\b/i, ' ')
          .gsub(/(?<![[:alnum:]])P[[:space:]]*\d+(?:[[:space:]]*(?:,|and|to)[[:space:]]*(?:P[[:space:]]*)?\d+)*/, ' ')
          .gsub(ACTION, ' ')
    end

    def match?(text)
      text.match?(ACTION) && values(text).match?(/\A[[:space:]|*]*\z/)
    end
  end

  EXTRA_TERRITORIAL_DEFINITION = 'As defined in Annex E to Recommendation ITU-T E.212, ' \
    'extra-territorial use of an MCC+MNC is the term used to describe the'.freeze
  EXTRA_TERRITORIAL_SITUATION = 'situation where an MCC+MNC that has been assigned to an operator in one ' \
    'country, Country A, is used in another country, Country B, through a base station established in Country B.'.freeze
  EXTRA_TERRITORIAL_LABELS = Set.new([
    EXTRA_TERRITORIAL_DEFINITION, EXTRA_TERRITORIAL_SITUATION,
    "#{EXTRA_TERRITORIAL_DEFINITION} #{EXTRA_TERRITORIAL_SITUATION}",
    'Extra-territorial use*** of MCC/MNC, Annex E to Recommendation ITU-T E.212',
    "MSIN: Mobile Subscription Identification Number / numéro d'identification d'abonnement mobile /",
    "MSIN: Mobile Subscription Identification Number / numéro d'identification d'abonnement mobile / número de",
    "MSIN: Mobile Subscription Identification Number / numéro d'identification d'abonnement mobile / número de identificación de suscripción al servicio móvil"
  ]).freeze
  GLOSSARY_LEGEND_TOKEN_SHAPES = Set.new([
    'mnc mobile network code code de reseau mobile indicativo de red para el servicio movil',
    'mcc mobile country code indicatif de pays du mobile indicativo de pais para el servicio movil mnc mobile network code code de reseau mobile indicativo de red para el servicio movil'
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
        NUMBERED_HEADER_ROWS.include?(cells.join(' | ')) ||
          (cells.any? && cells.all? { |c| c.empty? || HEADER_CELLS.include?(c) })
      }
    ),
    Rule.new(
      id: 'column_header_vocabulary',
      reason: 'complete fixed table captions in French/Spanish or longer wording; numeric footnote markers ' \
              'are allowed only in the full known heading shape',
      match: lambda { |_text, _tokens, cells|
        cells.join(' | ').match?(NUMBERED_COUNTRY_CODE_HEADER) ||
          (cells.any? && cells.all? { |c| c.empty? || HEADER_CELLS.include?(c) || ADDITIONAL_HEADER_CELLS.include?(c) })
      }
    ),
    Rule.new(
      id: 'ordering_directive',
      reason: 'printed insertion-order heading ("Numerical order ADD", "Alphabetical order ADD"); registers are ' \
              'keyed, not ordered, so the directive has no field in a patch',
      match: ->(_text, tokens, _cells) { tokens.to_a.sort.join(' ').match?(/\A(add|alphabetical|numeric|numerical|order)( (add|alphabetical|numeric|numerical|order))*\z/) && tokens.size <= 3 }
    ),
    Rule.new(
      id: 'page_action_heading',
      reason: 'page markers and fixed action/order directives only; country names, operator names and codes ' \
              'must still map to a patch',
      match: ->(text, _tokens, _cells) { PageHeading.match?(text) }
    ),
    Rule.new(
      id: 'extra_territorial_footnote',
      reason: 'definition footnote of the extra-territorial-use tables ("*** As defined in Annex E to Recommendation ' \
              'ITU-T E.212, extra-territorial use of an MCC+MNC ..."), boilerplate repeated on every such table; the ' \
              'extra-territorial use itself is carried by the patch rows',
      match: lambda { |text, _tokens, _cells|
        label = text.gsub(/[[:space:]]+/, ' ').strip.sub(/\A\*+[ ]*/, '')
        EXTRA_TERRITORIAL_LABELS.include?(label)
      }
    ),
    Rule.new(
      id: 'bulletin_reference_banner',
      reason: 'parenthesised pointer to another Operational Bulletin or Recommendation ("(Annex to ITU Operational ' \
              'Bulletin No. 1161 - 1.XII.2018)", "(According to Recommendation ITU-T Q.708 (03/1999))"); a ' \
              'cross-reference, not register content',
      match: ->(text, _tokens, _cells) { text.match?(/\A[[:space:]]*\((?:Annex to ITU Operational Bulletin No\. \d+ [–-] \d{1,2}\.[IVX]+\.\d{4}|According to Recommendation ITU-T Q\.708 \(\d{2}\/\d{4}\))\)[[:space:]]*\z/i) }
    ),
    Rule.new(
      id: 'list_viii_questionnaire_label',
      reason: 'numbered item label of the fixed List VIII Part III monitoring-station questionnaire ("2. Geographical ' \
              'coordinates", "9. Ranges of frequencies ..."): the same fourteen headings precede every station ' \
              'entry; the station values that follow them are what the patch stores',
      match: ->(text, _tokens, _cells) { text.match?(LIST_VIII_LABEL_ONLY) }
    ),
    Rule.new(
      id: 'glossary_legend',
      reason: 'trilingual legend of a column abbreviation ("MNC : Mobile Network Code / Code de reseau mobile / ' \
              'Indicativo de red ..."), repeated boilerplate; the abbreviation is a register field name',
      match: ->(text, _tokens, _cells) { GLOSSARY_LEGEND_TOKEN_SHAPES.include?(Tok.words(text).join(' ')) }
    ),
    Rule.new(
      id: 'page_cross_reference',
      reason: 'footnote pointing at another printed page of the Bulletin ("See the present ITU Operational ' \
              'Bulletin No. N, page 5"); a layout reference, not register content',
      match: ->(text, _tokens, _cells) { text.match?(/\A[[:space:]*]*See (?:(?:the present )?(?:ITU )?Operational Bulletin No\.? \d+(?: of \d{1,2}\.[IVX]+\.\d{4})?, page \d+|page \d+ of (?:the present )?(?:ITU )?Operational Bulletin No\.? \d+(?: of \d{1,2}\.[IVX]+\.\d{4})?)\.?[[:space:]]*\z/i) }
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
      reason: 'introductory sentence of the shared-country-code (881/882/883) identification-code table; the table ' \
              'rows carry the data',
      match: lambda { |text, _tokens, _cells|
        text.gsub(/[[:space:]]+/, ' ').strip.match?(
          /\A(?:[nopq] )?Associated with shared country code (?:881|882|883), the following (?:one|two|three|four)-digit identification(?: code)?(?: reservations? or assignments?| reservations?| assignments?| withdrawal)? (?:have been made for|has been made for|has been withdrawn from|have been withdrawn (?:from|for)|has been assigned for) the (?:international|GMSS) networks? of:\z/
        )
      }
    )
  ].freeze

  # ---- tokens --------------------------------------------------------

  module Tok
    module_function

    def fold(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{M}/, '').downcase
    end

    # A word and its detached suffix: "38 th" (ordinal), "m 2" / "T 0" (one
    # letter with a superscript or subscript digit; never "P 24", the page
    # marker). Printed text and patch values disagree on the space.
    JOINABLE = /(?<![[:alnum:]])(\d+(?=[[:space:]]+(?:st|nd|rd|th)(?![[:alnum:]]))|[a-oq-z](?=[[:space:]]+\d(?![[:alnum:]])))[[:space:]]+(st|nd|rd|th|\d)(?![[:alnum:]])/

    def words(str)
      fold(str).scan(/[[:alnum:]]+/)
    end

    # Patch side: the separate words plus the joined form (a superset).
    def of(str)
      folded = fold(str)
      toks = folded.scan(/[[:alnum:]]+/)
      folded.scan(JOINABLE) { |a, b| toks << (a + b) }
      toks
    end

    # Printed side: the joined form replaces its two words, so a patch holding
    # either spelling ("38th" or "38 th") carries it.
    def of_print(str)
      folded = fold(str)
      folded.gsub(JOINABLE) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}" }.scan(/[[:alnum:]]+/)
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
          next unless @register_slugs.include?(slug) || register_text?(path)
          next unless File.basename(path) == 'text.yaml' || File.basename(path).match?(ACTION_FILE)

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
      @register_slugs = Set.new(Array(reg).map { |r| r['source_slug'] || r['slug'] })
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

    # Text amendments can target registers not yet present in the catalog.
    def register_text?(path)
      return false unless File.basename(path) == 'text.yaml'

      data = YAML.safe_load(File.read(path), aliases: true,
                                              permitted_classes: [Date, Time, DateTime, Symbol])
      data.is_a?(Hash) && data['_class'] == 'TextAmendment'
    end

    def ob_issue_patch(path)
      kind = File.basename(path) == 'text.yaml' ? :text : :structured
      tokens, numbers = tokens_of_file(path)
      Patch.new(path: path, layer: :ob_issues, kind: kind, tokens: tokens, numbers: numbers)
    end

    def change_patch(path)
      tokens, numbers = tokens_of_file(path)
      Patch.new(path: path, layer: :changes, kind: :structured, tokens: tokens, numbers: numbers)
    end

    def tokens_of_file(path)
      data = YAML.safe_load(File.read(path), aliases: true,
                                              permitted_classes: [Date, Time, DateTime, Symbol])
      set = Set.new
      numbers = Set.new
      if File.basename(path) == 'text.yaml' && data.is_a?(Hash) && data['contents'].is_a?(Hash)
        # Verbatim ProseMirror: tokenise per printed line, the way the source
        # is, so "CS" + "3" in two text nodes is the token "cs3" on both sides.
        Extract.lines(data['contents']).each { |text, _| set.merge(Tok.with_unpadded(Tok.of(text))) }
      end
      collect(data, set, numbers)
      [set, numbers]
    rescue StandardError => e
      warn "coverage: cannot read #{path}: #{e.class}: #{e.message}"
      [Set.new, Set.new]
    end

    # A patch value that is only a telephone-style number ("+358 40 8668582"):
    # its digits with the grouping removed, so a printed regrouping
    # ("+358 40 866 8582") still meets it.
    PHONE_VALUE = /\A[+\d][\d +().\/-]*\d\z/

    def collect(node, set, numbers)
      case node
      when Hash then node.each_value { |v| collect(v, set, numbers) }
      when Array then node.each { |v| collect(v, set, numbers) }
      when Date, Time
        set.merge(Tok.date_tokens(node.year, node.month, node.day))
      when String
        set.merge(Tok.of_patch_value(node))
        digits = node.gsub(/\D/, '')
        numbers << digits if node.match?(PHONE_VALUE) && digits.size >= 6
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

      stripped = strip_labels(line) - regrouped_numbers(line, structured)
      if stripped.size < tokens.size && !stripped.empty?
        hit = pick(structured, stripped) ||
              (union_covers?(structured, stripped) ? structured.first : nil)
        return Result.new(line: line, status: :mapped_values_only, patch: hit) if hit
      end

      cells = (line.text.include?(' | ') ? line.text.split(' | ') : line.text.split(/[[:space:]]{2,}/))
              .map { |c| Tok.words(c).join(' ') }
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

    PHONE_RUN = /\+?\d[\d ().\/-]*\d/

    # Tokens of printed telephone numbers whose digits, grouping ignored, are
    # a patch's number: the patch keeps "+358 40 8668582", the print wraps it
    # "+358 40 866 8582".
    def regrouped_numbers(line, structured)
      numbers = structured.flat_map { |p| p.numbers.to_a }
      return Set.new if numbers.empty?

      covered = Set.new
      line.text.scan(PHONE_RUN) do |run|
        digits = run.gsub(/\D/, '')
        next unless digits.size >= 6 && numbers.include?(digits)

        covered.merge(Tok.with_unpadded(Tok.words(run)))
      end
      covered
    end

    def strip_labels(line)
      text = PageHeading.values(line.text)
      text = text.sub(LIST_VIII_LABEL, '') if line.slug == 'list-viii'
      text = text.gsub(/\(Formerly[[:space:]]+/i, '(') if line.slug == 'e164-cc'
      text = text.sub(/\A[[:space:]]*Country code(?: \(CC\))?[[:space:]]*\|/i, '')
      text = text.sub(/\A[[:space:]]*P[[:space:]]+(?=\d)/, '')
      text = text.gsub(/(?<![[:alnum:]])(?:Cell|Mobile|Telephone|Tel\.)[[:space:]]*:/i, ' ') # "Mobile:" contact label
      text = text.sub(/\A[^|]*:[[:space:]]*\|/, '')            # "Label: | value" form row
      text = text.sub(/\A[^|?]*\?[[:space:]]+(?=\S+\z)/, '')  # "Label? YES" form row
      toks = Tok.with_unpadded(Tok.of_print(text))
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
          tokens = Set.new(Tok.with_unpadded(Tok.of_print(text)))
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
