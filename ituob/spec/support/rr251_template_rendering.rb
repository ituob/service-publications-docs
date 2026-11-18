# frozen_string_literal: true

module Rr251TemplateRendering
  def render_rr251_template(template, countries, metadata, lang, group)
    country = countries.first.merge('data' => { 'groups' => { 'amateur' => [group] } })
    template.render!({ 'countries' => [country], 'metadata' => metadata, 'lang' => lang })
  end
end
