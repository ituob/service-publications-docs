# frozen_string_literal: true
module Ituob
  class Helpers

    def self.para_to_t(p)
      p.content.map{|x|x.text rescue ""}
    end

    def self.dump_table(tbl)
      # For each cell, join ALL text nodes of each paragraph so that
      # link text + parenthetical URL (common in T.35 related_links)
      # is preserved. Cells can also contain NESTED tables (List VIII
      # station detail sheets) — their flattened text is included as
      # an extra paragraph string instead of being dropped. Empty
      # cells produce [""], matching the original implementation so
      # callers that check cell count still work.
      tbl.content.map do |row|
        row.content.map do |cell|
          paras = cell.content.map do |node|
            case node.type
            when 'paragraph'
              texts = (node.content || []).map { |t| t.text.to_s.strip rescue "" }
              texts.reject(&:empty?).join(' ')
            when 'table'
              dump_table(node).flatten.map { |x| x.to_s.strip }.reject(&:empty?).join(' — ')
            end.to_s
          end
          paras.empty? ? [""] : paras
        end
      end
    end

    def self.split_str(str)
      str.split(/\p{Space}+/)
    end

    def self.split_str_normal(str)
      str.split(/ +/)
    end

    def self.split_str_normal_double(str)
      str.split(/  +/)
    end

    def self.replace_legacy_space(str)
      str.gsub(/\p{Space}/, ' ')
    end

    def self.strip_legacy(str)
      if str
        self.replace_legacy_space(str).strip
      end
    end

    # Normalize legacy (non-breaking) spaces, collapse whitespace
    # runs to single spaces, and strip. The canonical printed-text
    # cleanup shared by the paragraph-walk parsers.
    def self.normalize_whitespace(text)
      replace_legacy_space(text.to_s).gsub(/\s+/, ' ').strip
    end

    def self.remove_legacy_double_spaces(str)
      self.replace_legacy_space(str).split(/  +/).join(' ')
    end

    # isolate_key(['Tel: +49 7252 960', ...], "Tel") -> "+49 7252 960"
    # Returns the value following +key+ in the first matching string.
    # Tolerates the printed separator forms ("Tel:", "Tel.:", "E-mail:").
    def self.isolate_key(array_of_str, key)
      return nil if array_of_str.nil?
      key_pattern = Regexp.escape(key)
      matching_str = array_of_str.find { |x| x.to_s.match(/#{key_pattern}/i) }
      return nil unless matching_str

      replaced = replace_legacy_space(matching_str)
      # Strip the key prefix (e.g. "Tel.:", "Fax:", "Email:") and any
      # leading whitespace.
      replaced = replaced.sub(/#{key_pattern}[\s.:]*\s*/i, '')
      replace_legacy_space(replaced).strip
    end

    def self.grabcol2(arr_of_arr_of_1str, key)
      matching_row = arr_of_arr_of_1str.find{|x| x[0][0].match(/#{key}/)}
      if matching_row
        return matching_row[1][0]
      end
    end

    def self.dump_doc(doc)
      doc.content.map do |ct|
        case ct.type
        when 'paragraph'
          para_to_t(ct)
        when 'table'
          dump_table(ct)
        end
      end
    end

    def self.dump_doc_full(m)
      dump_doc(Prosereflect::Parser.parse_document(m))
    end

  end
end

