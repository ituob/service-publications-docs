# frozen_string_literal: true

module Ituob
  module Extractors
    # Generic ProseMirror extractor.
    #
    # This extractor handles ProseMirror content using three layout patterns
    # observed in OB source data:
    #
    # 1. Action keyword in cell — the first cell of a data row contains
    #    "<country> <ACTION>" (e.g. "Germany (Federal Republic of) ADD").
    # 2. Action keyword in paragraph between tables — a paragraph between
    #    tables sets the current action; the following table's rows are
    #    entries for that action.
    # 3. Action defaulted to ADD — no keyword anywhere; treat as ADD.
    #
    # The extractor emits one ChangeObject per (issue × action_type) pair,
    # with all matching entries grouped under +data['entries']+.
    class ProseMirror < Base
      include ProseMirrorWalker

      attr_reader :issue_id, :publication_id, :position_on

      # +amendment+ is a +Domain::Amendment+. +issue_id+ is the IssueId.
      def extract(amendment, issue_id:)
        @issue_id = issue_id.is_a?(Domain::Identifiers::IssueId) ? issue_id : Domain::Identifiers::IssueId.new(issue_id)
        @publication_id = amendment.publication_id
        @position_on = amendment.position_on

        doc = amendment.contents_en
        return [] unless doc.is_a?(Hash) && doc['content'].is_a?(Array)

        actions = walk_top_level(doc)
        actions.map { |a| to_change_object(a, amendment) }
      end

      private

      # Walk the doc's top-level children, returning a list of
      # { action_type:, entries: } hashes in document order.
      def walk_top_level(doc)
        actions = []
        current = nil

        each_top_level(doc) do |node|
          case node['type']
          when 'paragraph', 'heading'
            text = normalize_ws(node_text(node))
            next if text.empty?

            action_type = Catalogs::ActionTypes.find_last_in(text)
            next unless action_type

            country = text.sub(/\s+#{action_type}\s*\*?\z/i, '').strip
            current = { action_type: action_type, entries: [] }
            current[:entries] << { 'country_or_area' => { 'en' => country } } unless country.empty?
            actions << current
          when 'table'
            rows = extract_rows(node)
            next if rows.empty?

            data_rows = header?(rows.first) ? rows[1..] : rows
            data_rows.each do |row|
              action_type, action_idx = find_action_in_row(row)
              if action_type
                country = first_non_action_cell(row, action_idx)
                current = { action_type: action_type, entries: [] }
                current[:entries] << entry_from_row(row, action_idx) { |i| i == action_idx ? nil : { 'en' => country } }
                current[:entries].last.delete('col_0') if current[:entries].last.key?('col_0')
                actions << current
              else
                # Default to ADD when no action keyword present.
                current ||= { action_type: 'ADD', entries: [] }
                current[:entries] << entry_from_row(row)
                actions << current if actions.empty? || actions.last.object_id != current.object_id
              end
            end
          end
        end

        # Coalesce consecutive same-action_type entries (a paragraph + its
        # following table produces duplicates).
        coalesced = []
        actions.each do |a|
          last = coalesced.last
          if last && last[:action_type] == a[:action_type] && a[:entries].first && a[:entries].first.value?(a[:action_type])
            # Action paragraph prelude merges into the action that follows.
            next
          end
          if last && last[:action_type] == a[:action_type]
            last[:entries].concat(a[:entries])
          else
            coalesced << a.dup
          end
        end
        coalesced
      end

      def header?(row)
        text = row.join(' ').downcase
        %w[country code name address contact company network mcc mnc ispc sanc
           issuer carrier tel fax email url usage service destination
           geographical].any? { |kw| text.include?(kw) }
      end

      def find_action_in_row(row)
        row.each_with_index do |cell, i|
          a = Catalogs::ActionTypes.find_last_in(cell)
          return [a, i] if a
        end
        [nil, -1]
      end

      def first_non_action_cell(row, action_idx)
        row.each_with_index do |cell, i|
          next if i == action_idx

          return cell unless cell.strip.empty?
        end
        ''
      end

      def entry_from_row(row, _action_idx = nil)
        entry = {}
        row.each_with_index do |cell, i|
          entry[i.zero? ? 'country_or_area' : "col_#{i}"] = i.zero? ? { 'en' => cell } : cell
        end
        entry
      end

      def to_change_object(action_hash, amendment)
        Domain::ChangeObject.new(
          action_type: action_hash[:action_type],
          issue_id: issue_id,
          publication_id: publication_id,
          position_on: position_on,
          identifier: Domain::Identifiers::RecordCode.new("#{issue_id}-000"),
          data: {
            '_class' => self.class.name,
            'publication' => publication_id.value,
            'entries' => action_hash[:entries],
          },
          source: :parsed,
          note: 'Re-extracted via Ituob::Extractors::ProseMirror from source content',
        )
      end
    end
  end
end
