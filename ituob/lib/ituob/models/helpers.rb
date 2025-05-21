module Ituob
  class Helpers

    def self.para_to_t(p)
      p.content.map{|x|x.text rescue ""}
    end

    def self.dump_table(tbl)
      tbl.content.map{|x|x.content.map{|y|y.content.map{|z|z.content[0].text.strip rescue ""}}}
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

    def self.remove_legacy_double_spaces(str)
      self.replace_legacy_space(str).split(/  +/).join(' ')
    end

    # isolate_key(['Foo: 123', 'Bar: 456'], "Foo") -> "123"
    def self.isolate_key(array_of_str, key)
      matching_str = array_of_str.find{|x|x.match(/${key}/)}
      if matching_str
        matching_str = self.replace_legacy_space(matching_str.gsub('Email:',''))
      end

      matching_str
    end

    def self.grabcol2(arr_of_arr_of_1str, key)
      matching_row = arr_of_arr_of_1str.find{|x| x[0][0].match(/#{key}/)}
      if matching_row
        return matching_row[1][0]
      end
    end

  end
end

