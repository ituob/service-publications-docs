# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ituob do
  describe 'autoload setup' do
    it 'exposes Commands namespace via autoload' do
      expect(Ituob::Commands).to eq(Ituob::Commands)
    end

    it 'exposes Commands::Dataset subcommand via autoload' do
      expect(Ituob::Commands::Dataset).to be_a(Class)
      expect(Ituob::Commands::Dataset.ancestors).to include(Thor)
    end

    it 'exposes Commands::Schema subcommand via autoload' do
      expect(Ituob::Commands::Schema).to be_a(Class)
      expect(Ituob::Commands::Schema.ancestors).to include(Thor)
    end

    it 'exposes Cli entry point via autoload' do
      expect(Ituob::Cli).to be_a(Class)
      expect(Ituob::Cli.ancestors).to include(Thor)
    end

    it 'exposes Dataset (legacy validation class) via autoload' do
      expect(Ituob::Dataset).to be_a(Class)
    end
  end

  describe 'no internal require_relative' do
    it 'does not use require_relative for internal code' do
      lib_dir = File.expand_path('../lib/ituob', __dir__)
      pattern = "#{lib_dir}/**/*.rb"
      violations = Dir.glob(pattern).select do |path|
        next false if File.basename(path) == 'version.rb'

        File.foreach(path).any? { |line| line.strip.start_with?('require_relative') }
      end
      expect(violations).to be_empty,
                            "Found require_relative in #{violations.inspect}"
    end

    it 'does not require internal ituob paths from cli/commands' do
      cli_path = File.expand_path('../lib/ituob/cli.rb', __dir__)
      commands_path = File.expand_path('../lib/ituob/commands.rb', __dir__)
      [cli_path, commands_path].each do |path|
        next unless File.exist?(path)

        content = File.read(path)
        internal_requires = content.scan(/^\s*require\s+["'](ituob\/[^"']+)["']/)
        expect(internal_requires).to be_empty,
                                     "#{path} requires internal ituob paths: #{internal_requires.inspect}"
      end
    end
  end
end
