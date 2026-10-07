#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Strip every `require_relative` line from lib/ files. The classes those
# requires were loading are now autoloaded via parent namespace files.

require 'pathname'

LIB_ROOT = Pathname.new(File.expand_path('../ituob/lib', __dir__))

count = 0
LIB_ROOT.glob('**/*.rb').each do |path|
  next if path == LIB_ROOT + 'ituob.rb' # top-level entry, keeps framework requires

  original = path.read
  # Remove every require_relative line. Keep require lines for gems.
  new_content = original.each_line.reject do |line|
    line.strip.start_with?('require_relative')
  end.join

  # Also remove leading blank lines left behind.
  new_content = new_content.sub(/\A\n+/, '')

  if new_content != original
    path.write(new_content)
    count += 1
    puts "cleaned #{path.relative_path_from(LIB_ROOT)}"
  end
end

puts
puts "Cleaned #{count} files"
