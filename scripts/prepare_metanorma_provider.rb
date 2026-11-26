#!/usr/bin/env ruby
# frozen_string_literal: true

# Run without the image's RUBYOPT/BUNDLE_GEMFILE so its old bundle cannot
# hide the gems being installed. Reuse the image bundle and native gems;
# ituob/Gemfile.lock belongs to a different dependency environment.
require 'ripper'

module MetanormaProviderSetup
  # The first release with the data provider registry. Older images ship an
  # earlier plugin, so this version is installed; newer images' metanorma-cli
  # requires a later plugin (1.18.7 needs ~> 0.7.80), so the Gemfile accepts
  # any version from here up and Bundler picks the one metanorma-cli allows.
  PLUGIN_VERSION = '0.7.72'

  def self.prepare_gemfile(path, provider_path)
    source = File.read(path)
    declarations = {
      'ituob' => "gem \"ituob\", path: #{provider_path.dump}",
      'metanorma-plugin-lutaml' => "gem \"metanorma-plugin-lutaml\", \">= #{PLUGIN_VERSION}\""
    }
    declarations.each do |name, replacement|
      pattern = /^[ \t]*gem[ \t]+(['"])#{Regexp.escape(name)}\1[^\n]*(?:\n|\z)/
      matches = source.scan(pattern)
      raise "Duplicate #{name} declarations in #{path}" if matches.size > 1

      source = source.sub(pattern) do |declaration|
        last_token = Ripper.lex(declaration).reverse.find do |token|
          !%i[on_sp on_nl on_ignored_nl on_comment].include?(token[1])
        end
        if last_token&.dig(1) == :on_comma || declaration.rstrip.end_with?('\\')
          raise "Multiline #{name} declaration in #{path}; cannot safely replace it"
        end
        "#{replacement}\n"
      end
      source += "\n#{replacement}\n" if matches.empty?
    end
    File.write(path, source)
  end

  def self.run!(*command, environment: {})
    return if system(environment, *command)

    abort "Provider setup failed: #{command.join(' ')}"
  end

  def self.prepare
    gemfile = File.expand_path(ENV.fetch('METANORMA_GEMFILE', '/setup/Gemfile'))
    provider_path = File.expand_path('../ituob', __dir__)
    # Only the missing pure Ruby dependencies are added. --conservative keeps
    # installed dependencies, including the image's compiled native gems.
    [['json-schema', '~> 3.0'], ['colorize', '~> 0.8'],
     ['prosereflect', nil], ['metanorma-plugin-lutaml', PLUGIN_VERSION]].each do |name, version|
      command = ['gem', 'install', '--no-document', '--conservative', name]
      command += ['--version', version] if version
      run!(*command)
    end
    prepare_gemfile(gemfile, provider_path)
    environment = { 'BUNDLE_GEMFILE' => gemfile, 'RUBYOPT' => nil }
    run!('bundle', 'install', '--local', environment: environment)
    # Exercise lazy Gem.find_files discovery inside the exact rendering bundle.
    # A successful `require "ituob"` outside Bundler does not prove this works.
    preflight = <<~'PREFLIGHT'
      require 'liquid'
      require 'metanorma/plugin/lutaml/data_providers'
      registry = Metanorma::Plugin::Lutaml::DataProviders
      publication = registry.query('ituob', 'publication', register: 'm1400-icc', as_of: 1060)
      abort "Provider lost publication rows: #{publication.items.size}" unless publication.items.size == 1164
      abort 'Provider metadata is missing' if publication.metadata&.title&.en.to_s.empty?
      puts "ituob provider discovered: #{publication.items.size} rows; metanorma-plugin-lutaml #{Gem.loaded_specs.fetch('metanorma-plugin-lutaml').version}"
    PREFLIGHT
    run!('bundle', 'exec', 'ruby', '-e', preflight, environment: environment)
  end
end

MetanormaProviderSetup.prepare if $PROGRAM_NAME == __FILE__
