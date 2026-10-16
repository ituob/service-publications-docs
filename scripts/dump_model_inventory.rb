#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Dumps the effective model inventory of the ituob gem: for every
# Ituob::Models::* lutaml-model class, its superclass, attributes
# (type, collection, default), own behavior surface (instance +
# singleton methods), and key_value mapping rules (wire name,
# render_default/render_nil).
#
# Output: JSON on stdout (or to the file given as ARGV[0]).
#
# Used to author and re-verify ituob/ontology/messages.lml — the
# drift guard spec consumes the same shape.

$LOAD_PATH.unshift(File.expand_path('../ituob/lib', __dir__))
require 'ituob'
require 'json'

def behavior_surface(klass)
  (klass.instance_methods(false) + klass.private_instance_methods(false)).sort +
    klass.singleton_methods(false).map { |m| "self.#{m}" }
end

def mapping_rules(klass, format)
  mapping = klass.public_send(:mappings_for, format) rescue nil
  return [] unless mapping

  Array(mapping&.rules).map do |rule|
    {
      wire: rule.from.to_s,
      to: rule.to.to_s,
      render_default: !!rule.render_default,
      render_nil: !!rule.render_nil,
    }
  end
rescue StandardError
  []
end

# Force every autoload declared on the module to resolve first —
# several model files define sibling classes (IssueContact, IssueAuthor,
# TextAction, ...) that only appear once their host file loads.
def eager_load!(mod)
  mod.constants.each { |c| mod.const_get(c) rescue nil }
end

# lutaml's attribute macro injects non-model constants into the
# defining namespace; they are not part of the ontology.
LUTAML_INJECTED = %w[ACTION_CLASS GENERATOR_STATE_KEY].freeze

def serializable_classes(mod, prefix = [])
  out = []
  mod.constants.sort.each do |const|
    next if LUTAML_INJECTED.include?(const.to_s)

    k = mod.const_get(const)
    case k
    when Class
      out << [const.to_s, k] if k < Lutaml::Model::Serializable
      out.concat(serializable_classes(k, prefix + [const])) if k.name.to_s.start_with?('Ituob::')
    when Module
      out.concat(serializable_classes(k, prefix + [const]))
    end
  end
  out
end

inventory = {}

eager_load!(Ituob::Models)
serializable_classes(Ituob::Models).each do |name, klass|

  attrs = klass.attributes.transform_values do |attr|
    {
      type: attr.type.is_a?(Class) ? attr.type.name.split('::').last : attr.type.to_s,
      collection: !!attr.collection?,
      default: attr.options[:default].is_a?(Proc) ? '<proc>' : attr.options[:default].inspect,
    }
  end

  record = {
    superclass: klass.superclass.name,
    attributes: attrs,
    behavior: behavior_surface(klass),
    yaml_mapping: mapping_rules(klass, :yaml),
  }
  inventory[name] = record
end

out = JSON.pretty_generate(inventory)
if ARGV[0]
  File.write(ARGV[0], out)
  warn "wrote #{ARGV[0]} (#{inventory.size} classes)"
else
  puts out
end
