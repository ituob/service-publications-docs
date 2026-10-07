# frozen_string_literal: true

require 'prosereflect'

module Ituob
  module Models
    class E164CCAmendment < Amendment
      attribute :actions, E164CCAction, collection: true
      attribute :_class, :string, default: -> { self.name.split('::').last }

      key_value do
        map '_class', to: :_class, render_default: true
        map 'position_on', to: :position_on
        map 'actions', to: :actions
      end

      # Walk state for one document parse — the active action. Held in
      # a plain object so parse keeps no class-level state (reentrant).
      class State
        attr_accessor :action
      end

      def self.parse(hash, position_on: nil, dataset_code: nil)
        amendment = new

        # Set the position_on if it exists
        amendment.position_on = position_on if position_on

        doc = Prosereflect::Parser.parse_document(hash)

        state = State.new
        state.action = E164CCAction.new
        state.action.entries = []
        amendment.actions << state.action

        simplified_doc = Ituob::Helpers.dump_doc(doc)

        simplified_doc.each_with_index do |c, ci|
          next if c.nil?
          raise "Unexpected non-array item" unless c.is_a?(Array)

          first_elem = c[0]
          if first_elem.is_a?(String)
            fixed_str = Ituob::Helpers.replace_legacy_space(c.join(' '))

            if first_elem.length < 3
              next
            elsif fixed_str.match(/^[onpq] /)
              state.action.note = (state.action.note || "") + fixed_str
            else
              next if !(first_elem.match(/^P/) || first_elem.match(/Note /))

              basestr = c.join('')
              segs = Ituob::Helpers.split_str(basestr)

              state.action.note = segs[1]
              state.action.position = segs[0..1].join(" ")
              if m = basestr.match(/[A-Z]{3}\*$/)
                state.action.action_type = m[0].to_s
              elsif m = basestr.match(/[A-Z]{3}$/)
                state.action.action_type = m[0].to_s
              elsif segs[-1].length == 3
                state.action.action_type = segs[-1]
              else
                state.action.action_type = basestr[-3..-1]
              end
            end

          elsif first_elem.is_a?(Array) # table
            c[1..].each do |row|
              next unless row.length >= 4
              segs = row.map { |cell| cell.is_a?(Array) ? cell.join(' ').strip : cell.to_s.strip }
              entry = E164CCEntry.new
              entry.applicant = segs[0]
              entry.network = segs[1]
              entry.cc_ic = segs[2]
              entry.status = segs[3]
              entry.action_date = segs[4] if segs[4] && !segs[4].empty?
              entry.reclamation_date = segs[5] if segs[5] && !segs[5].empty?
              if entry.applicant.match(/Formerly/)
                entry.applicant = segs[0].match(/([^(]*)/).to_s.strip
                entry.formerly = segs[0].match(/\((.*)\)/)[1].gsub('Formerly ','').strip
              end
              state.action.entries << entry
            end
            state.action = E164CCAction.new
            state.action.entries = []
            amendment.actions << state.action
          else
            next if first_elem.nil?
            raise "Unexpected non-string/array elem in c[0]"
          end
        end

        amendment
      end

    end
  end
end
