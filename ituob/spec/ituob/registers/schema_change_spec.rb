# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'json-schema'

RSpec.describe 'schema-change.yaml' do
  let(:schema_path) do
    File.expand_path('../../../../datasets/schema-change.yaml', __dir__)
  end
  let(:schema) do
    s = YAML.safe_load(File.read(schema_path), aliases: true)
    s.delete('$schema')
    s.delete('id')
    s
  end

  def validate(hash)
    JSON::Validator.fully_validate(schema, hash, errors_as_objects: true)
  end

  let(:base) do
    {
      'register' => 'F1',
      'ob_issue_no' => '700',
      'identifier' => { 'code' => 'ABC' },
    }
  end

  # The json-schema Ruby gem does not fully support Draft-07
  # if/then conditionals. These specs test what it CAN enforce:
  # the enum on +type+, the required top-level fields, and basic
  # structural validity. Per-action conditional enforcement (ADD
  # requires data, LIR requires reason) is validated by the
  # replay engine's strategies, not by the schema validator.

  context 'type enum' do
    it 'accepts all 7 action types' do
      %w[ADD SUP REP LIR MOD DEL SEED].each do |t|
        hash = base.merge('type' => t)
        hash['data'] = { 'x' => 1 } if %w[ADD REP MOD SEED].include?(t)
        hash['reason'] = { 'en' => 'x' } if t == 'LIR'
        errors = validate(hash)
        expect(errors).to be_empty, "expected #{t} to be valid, got: #{errors.map { |e| e[:message] }.inspect}"
      end
    end

    it 'rejects unknown type' do
      errors = validate(base.merge('type' => 'BADTYPE'))
      expect(errors).not_to be_empty
    end
  end

  context 'required fields' do
    it 'rejects without type' do
      errors = validate(base.reject { |k, _| k == 'type' }.merge('data' => {}))
      expect(errors).not_to be_empty
    end

    it 'rejects without register' do
      errors = validate({ 'type' => 'ADD', 'ob_issue_no' => '700',
                          'identifier' => { 'code' => 'X' }, 'data' => {} })
      expect(errors).not_to be_empty
    end

    it 'rejects without ob_issue_no' do
      errors = validate({ 'type' => 'ADD', 'register' => 'F1',
                          'identifier' => { 'code' => 'X' }, 'data' => {} })
      expect(errors).not_to be_empty
    end

    it 'rejects without identifier' do
      errors = validate({ 'type' => 'ADD', 'register' => 'F1',
                          'ob_issue_no' => '700', 'data' => {} })
      expect(errors).not_to be_empty
    end
  end

  context 'identifier' do
    it 'accepts direct code identifier' do
      errors = validate(base.merge('type' => 'ADD', 'data' => {},
                                    'identifier' => { 'code' => 'ABC' }))
      expect(errors).to be_empty
    end

    it 'accepts query identifier' do
      errors = validate(base.merge(
        'type' => 'ADD', 'data' => {},
        'identifier' => { 'query' => { 'field' => 'name', 'value' => 'test' } },
      ))
      expect(errors).to be_empty
    end

    it 'rejects identifier without code or query' do
      errors = validate(base.merge('type' => 'ADD', 'data' => {},
                                    'identifier' => {}))
      expect(errors).not_to be_empty
    end
  end

  context 'merge_strategy enum' do
    it 'accepts replace_fields' do
      errors = validate(base.merge('type' => 'MOD', 'data' => {},
                                    'merge_strategy' => 'replace_fields'))
      expect(errors).to be_empty
    end

    it 'accepts replace_full' do
      errors = validate(base.merge('type' => 'MOD', 'data' => {},
                                    'merge_strategy' => 'replace_full'))
      expect(errors).to be_empty
    end
  end
end
