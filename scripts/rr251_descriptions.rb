#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

# Source comments are authoritative. Keep YAML serialization out of the update
# path: anchors, quoting, comments and criteria must retain their original bytes.
module Rr251Descriptions
  HEADING = /\A(amateur|experimental) stations(?:\s+and\s+(amateur|experimental) stations)?\s*(?::\s*(.*))?\z/i
  BOUNDARY = /\A(?:notes?\b|(?:digits?|letters?|numbers?)\s+indicating\b|prefix\s+digit\b|\*|\[|(?:amateur|experimental)\s*:|[-:]\s*\z)/i

  def self.extract(source)
    comments = source.split(/^groups:\s*$/, 2).first.lines.filter_map do |line|
      line[/^\s*#\s?(.*)$/, 1]&.strip
    end
    # A heading can wrap between its two station kinds, even without spaces
    # following the comment marker.
    comments = comments.join("\n").gsub(/(amateur|experimental) stations and\s*\n\s*(amateur|experimental) stations/i, '\1 stations and \2 stations').lines.map(&:strip)
    result = {}
    active = []
    comments.each do |line|
      if (heading = HEADING.match(line))
        active = heading.captures.first(2).compact.map(&:downcase)
        active.each { |kind| result[kind] = heading[3].to_s.strip }
      elsif line.empty? || BOUNDARY.match?(line)
        active = []
      else
        active.each { |kind| result[kind] = [result[kind], line].reject(&:empty?).join(" ") }
      end
    end
    result.transform_values { |text| text.gsub(/\s+/, " ").strip }.reject { |_kind, text| text.empty? }
  end

  def self.issues(source)
    prose = extract(source)
    groups = YAML.safe_load(source, aliases: true).fetch("groups", {})
    groups.flat_map do |kind, entries|
      entries.each_with_index.filter_map do |entry, index|
        description = entry["description"]
        if description && (entries.length != 1 || description != prose[kind])
          "#{kind}[#{index}]: description differs from complete source prose or has ambiguous groups"
        elsif description && incomplete?(description)
          "#{kind}[#{index}]: description is too short or ends mid-sentence"
        elsif entries.length == 1 && prose[kind] && !description
          "#{kind}[#{index}]: missing description"
        end
      end
    end
  end

  def self.update(source)
    prose = extract(source)
    document = Psych.parse(source).root
    groups = pairs(document)["groups"]
    return source unless groups

    offsets = [0]
    source.lines.each { |line| offsets << offsets.last + line.bytesize }
    edits = []
    pairs(groups).each do |kind, sequence|
      next unless prose[kind] && sequence.is_a?(Psych::Nodes::Sequence) && sequence.children.length == 1

      mapping = sequence.children.first
      fields = pairs(mapping)
      description = fields["description"]
      if description
        start = offsets[description.start_line] + source.lines[description.start_line][0, description.start_column].bytesize
        finish = offsets[description.end_line] + source.lines[description.end_line].to_s[0, description.end_column].to_s.bytesize
        replacement = JSON.generate(prose[kind])
        replacement += source.byteslice(start...finish)[/\r?\n\z/].to_s
        edits << [start, finish, replacement]
      else
        key = mapping.children.each_slice(2).find { |name, _value| name.value == "regex" }&.first
        next unless key

        value = fields.fetch("regex")
        position = offsets[value.end_line + 1]
        newline = source.include?("\r\n") ? "\r\n" : "\n"
        separator = position == source.bytesize && !source.end_with?("\n") ? newline : ""
        edits << [position, position, "#{separator}#{' ' * key.start_column}description: #{JSON.generate(prose[kind])}#{newline}"]
      end
    end
    edits.sort_by(&:first).reverse_each.reduce(source.b) do |text, (start, finish, replacement)|
      text.byteslice(0, start) + replacement.b + text.byteslice(finish..).to_s
    end.force_encoding(source.encoding)
  end

  # The printed source sometimes consists entirely of compact call-sign ranges.
  # Those complete ranges are the only exception to the five-word prose floor.
  def self.incomplete?(description)
    ranges = /\A[A-Z0-9]+[-–][A-Z0-9]+\**(?: [A-Z0-9]+[-–][A-Z0-9]+\**)*\z/
    (description.split.length < 5 && !ranges.match?(description)) ||
      /\b(?:and|or|by|followed|\d+)\z/i.match?(description)
  end
  private_class_method :incomplete?

  def self.pairs(mapping)
    mapping.children.each_slice(2).to_h { |key, value| [key.value, value] }
  end
  private_class_method :pairs
end

if $PROGRAM_NAME == __FILE__
  check = ARGV.delete("--check")
  paths = ARGV.empty? ? Dir[File.expand_path("../datasets/1154-RR.25.1/data/*.yaml", __dir__)] : ARGV
  errors = paths.flat_map do |path|
    source = File.read(path)
    if check
      Rr251Descriptions.issues(source).map { |issue| "#{path}: #{issue}" }
    else
      updated = Rr251Descriptions.update(source)
      File.write(path, updated) if updated != source
      []
    end
  end
  errors.each { |error| warn error }
  exit(errors.empty? ? 0 : 1)
end
