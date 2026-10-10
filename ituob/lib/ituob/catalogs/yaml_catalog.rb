# frozen_string_literal: true

require 'yaml'

module Ituob
  module Catalogs
    # Mixin for YAML-backed catalogs.
    #
    # Encapsulates the lazy-load + index-by-key pattern that
    # +Registers+ and +Recommendations+ previously each duplicated.
    # Mix into a module's singleton class via:
    #
    #   class << self
    #     include YamlCatalog
    #   end
    #
    # Hosts must provide:
    # * +yaml_key+ — top-level key in the YAML (e.g. +'registers'+).
    # * +default_path+ — absolute path to the YAML file.
    # * +build_entry(hash)+ — entry factory. Receives a parsed Hash
    #   from the YAML list; returns an +Entry+ instance.
    # * +primary_key+ — symbol naming the +Entry+ field used as the
    #   lookup index (e.g. +:register_id+, +:code+).
    #
    # Hosts can declare additional indices from +declare_indices+ by
    # calling +index_by(:slug)+ etc. +find_by(index_name, key)+ is the
    # corresponding reader.
    module YamlCatalog
      # All known entries, indexed by their primary key.
      def all
        ensure_loaded!
        primary_index.values
      end

      # Find an entry by its primary key value.
      def find(key)
        ensure_loaded!
        primary_index[key.to_s]
      end

      # Iterate every entry. Returns an Enumerator if no block.
      def each(&block)
        ensure_loaded!
        return to_enum(:each) unless block_given?

        primary_index.each_value(&block)
      end

      def all_keys
        ensure_loaded!
        primary_index.keys
      end

      # Find by an alternate index declared via +index_by+.
      def find_by(index_name, key)
        ensure_loaded!
        idx = indices[index_name.to_sym]
        return nil unless idx

        idx[key.to_s]
      end

      # Force a (re)load from disk. Pass +path:+ to override the
      # default path (used by specs).
      def load!(path: nil)
        path ||= default_path
        data = Ituob::Support::Yaml.safe_load_file(path)
        list = (data || {}).fetch(yaml_key, [])
        reset!
        list.each do |h|
          entry = build_entry(h)
          primary_index[public_lookup_key(entry).to_s] = entry
          register_secondary_indices(entry)
        end
        @loaded = true
        self
      end

      def ensure_loaded!
        load! unless @loaded
      end

      def reset!
        @loaded = false
        @primary_index = {}
        @indices = {}
        declare_indices
      end

      # -- Hooks hosts override --------------------------------------

      # @return [String] top-level YAML key (e.g. +'registers'+).
      def yaml_key
        raise NotImplementedError, "#{self}.yaml_key not implemented"
      end

      # @return [String] absolute path to the YAML file.
      def default_path
        raise NotImplementedError, "#{self}.default_path not implemented"
      end

      # @return [Symbol] primary-key Entry field name.
      def primary_key
        raise NotImplementedError, "#{self}.primary_key not implemented"
      end

      # Build an +Entry+ from a parsed Hash row.
      def build_entry(_hash)
        raise NotImplementedError, "#{self}.build_entry not implemented"
      end

      # Declare additional indices via +index_by+. Hosts override to
      # call +index_by(:slug, :other_field)+ on reset.
      def declare_indices; end

      # -- State (private to the host) -------------------------------

      def primary_index
        @primary_index ||= begin
          reset!
          @primary_index
        end
      end

      def indices
        @indices ||= {}
      end

      # Hook for hosts to declare a secondary index. Call from
      # +declare_indices+ (e.g. +index_by :slug+).
      def index_by(field)
        indices[field.to_sym] = {}
      end

      def register_secondary_indices(entry)
        indices.each do |field, idx|
          value = entry[field]
          next if value.nil?

          idx[value.to_s] = entry
        end
      end

      def public_lookup_key(entry)
        entry[primary_key]
      end
    end
  end
end
