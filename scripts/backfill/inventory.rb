# frozen_string_literal: true

require 'set'

module Backfill
  # Class rules for the backfill inventory (spd#149). Pure functions: no disk I/O.
  module Inventory
    FIRST = 1
    LAST = 1343
    ISSUES_PER_YEAR = 24
    MONTHS_PER_ISSUE = 12.0 / ISSUES_PER_YEAR

    module_function

    # [year, month] from a publication_date string ("1998-06-01" or "2010-10-01T18:40:24.637Z").
    def year_month(publication_date)
      m = publication_date.to_s.match(/\A(\d{4})-(\d{2})/)
      m && [m[1].to_i, m[2].to_i]
    end

    # held: { number => publication_date string }. Returns the entry for every number FIRST..LAST.
    # Class b/c/d are never assigned here: they need evidence this module does not see.
    def classify(held, reference_docs: [])
      anchors = held.filter_map { |n, d| (ym = year_month(d)) && [n, ym] }.sort.to_h
      docs = reference_docs.to_set
      (FIRST..LAST).map { |n| entry(n, held.key?(n), anchors, docs.include?(n)) }
    end

    def entry(number, held, anchors, doc)
      evidence = []
      if held
        year, = anchors[number]
        evidence << "ob-issues/#{number}/meta.yaml"
        source = year ? 'publication_date' : 'unknown'
      else
        year = estimate_year(number, anchors)
        evidence << 'no ob-issues directory'
        source = year ? 'estimated' : 'unknown'
      end
      evidence << "itu-ob-data/reference-docs holds OB.#{number}" if doc
      {
        'number' => number,
        'class' => held ? 'a' : 'unresolved',
        'expected_year' => year,
        'year_source' => source,
        'local_evidence' => { 'ob_issues_dir' => held, 'reference_doc' => doc },
        'evidence' => evidence
      }
    end

    # Twice-monthly schedule anchored on the nearest dated held issue (the lower one on a tie).
    def estimate_year(number, anchors)
      return nil if anchors.empty?

      nearest = anchors.keys.min_by { |a| [(a - number).abs, a] }
      year, month = anchors[nearest]
      months = year * 12 + (month - 1) + ((number - nearest) * MONTHS_PER_ISSUE).floor
      months / 12
    end
  end
end
