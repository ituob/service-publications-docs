# frozen_string_literal: true

require 'json'

module ProviderPublicationRendering
  def render_provider_publication(source, directory, provider)
    environment = Liquid::Environment.build do |env|
      env.file_system = Liquid::LocalFileSystem.new(directory, '_%s.liquid')
    end
    source.gsub(/^\[lutaml_data,provider:ituob.(edition|publication),edition,options=(\{[^\n]*\})\]\n----\n(.*?)\n----/m) do
      arguments = JSON.parse(Regexp.last_match(2)).fetch('arguments').transform_keys(&:to_sym)
      query = Regexp.last_match(1)
      body = Regexp.last_match(3)
      edition = provider.public_send(query, **arguments)
      Liquid::Template.parse(body, environment: environment).render!('edition' => edition.to_liquid)
    end
  end

  def render_publication_table(directory, name, rows, metadata, language)
    environment = Liquid::Environment.build do |env|
      env.file_system = Liquid::LocalFileSystem.new(directory, '_%s.liquid')
    end
    source = '{% render "' + name + '", data: data, metadata: metadata, lang: lang %}'
    Liquid::Template.parse(source, environment: environment).render!(
      'data' => rows, 'metadata' => metadata, 'lang' => language
    )
  end
end
