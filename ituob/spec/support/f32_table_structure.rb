# frozen_string_literal: true

require "asciidoctor"
require "asciidoctor/logging"

module F32TableStructure
  def render_rows(rows, lang = "en")
    environment = Liquid::Environment.build do |env|
      env.file_system = Liquid::LocalFileSystem.new(dir, "_%s.liquid")
    end
    source = "{% assign lang = \"#{lang}\" %}{% render \"table\", data: rows, lang: lang %}"
    Liquid::Template.parse(source, environment: environment).render("rows" => rows)
  end

  def row(country, code, name: "Office", **extra)
    { "country_or_area" => { "en" => country, "fr" => country, "es" => country },
      "network_roa" => "ROA", "network_code" => code[0, 2], "office_code" => code,
      "telegraph_office_name" => { "en" => name } }.merge(extra.transform_keys(&:to_s))
  end

  def parse_f32_tables(source)
    previous_logger = Asciidoctor::LoggerManager.logger
    logger = Asciidoctor::MemoryLogger.new
    Asciidoctor::LoggerManager.logger = logger
    document = Asciidoctor.load(source, safe: :safe)
    [document.find_by(context: :table), logger.messages]
  ensure
    Asciidoctor::LoggerManager.logger = previous_logger
  end

  # Count logical columns, including slots occupied by earlier rowspans. A
  # complete physical row may have fewer than five cells but must fill the grid.
  def f32_table_grid_errors(table)
    errors = []
    table.rows.to_h.each do |group, rows|
      occupied = Array.new(5, 0)
      rows.each_with_index do |row, index|
        column = 0
        row.each do |cell|
          column += 1 while column < 5 && occupied[column].positive?
          width = cell.colspan || 1
          if column + width > 5 || occupied.slice(column, width).any?(&:positive?)
            errors << "#{group} row #{index}: cell overlaps or exceeds five columns"
            break
          end
          width.times { |offset| occupied[column + offset] = cell.rowspan || 1 }
          column += width
        end
        errors << "#{group} row #{index}: unfilled column" unless occupied.all?(&:positive?)
        occupied.map! { |remaining| [remaining - 1, 0].max }
      end
      errors << "#{group}: rowspan crosses row-group boundary" if occupied.any?(&:positive?)
    end
    errors
  end
end
