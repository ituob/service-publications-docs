# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

# Runs the real scripts/build_ob_issues.rb as a subprocess over a tiny real
# itu-ob-data tree. The script is copied into a scratch repo layout so its
# scripts/output report lands in the scratch dir, not in the checkout.
RSpec.describe 'scripts/build_ob_issues.rb CUTOVER_EDITION guard' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def seed_legacy(root, ids)
    ids.each do |id|
      dir = File.join(root, 'issues', id.to_s)
      write(File.join(dir, 'meta.yaml'), "id: #{id}\ndate: 2020-01-01\n")
      write(File.join(dir, 'general.yaml'), <<~YAML)
        messages:
        - type: custom
          title: legacy message #{id}
      YAML
      write(File.join(dir, 'amendments.yaml'), <<~YAML)
        messages:
        - type: amendment
          target:
            publication: ZZZ_TEST
            position_on: 2020-01-01
          contents:
            en: legacy amendment #{id}
      YAML
    end
  end

  def run_build(scratch, data_root, out_root, env = {})
    env = { 'ITU_OB_DATA_ROOT' => data_root, 'OB_ISSUES_OUT_PATH' => out_root,
            'CUTOVER_EDITION' => nil }.merge(env)
    Open3.capture3(env, RbConfig.ruby, File.join(scratch, 'scripts/build_ob_issues.rb'))
  end

  def manifest_stats
    YAML.load_file(File.join(@out, 'manifest.yaml'), permitted_classes: [Symbol, Time])['stats']
  end

  def tree(root, except: [])
    Dir.glob('**/*', File::FNM_DOTMATCH, base: root).sort.each_with_object({}) do |rel, h|
      next if except.include?(rel) || File.directory?(File.join(root, rel))

      h[rel] = File.read(File.join(root, rel))
    end
  end

  around do |ex|
    Dir.mktmpdir('cutover-spec') do |dir|
      @scratch = File.join(dir, 'repo')
      FileUtils.mkdir_p(File.join(@scratch, 'scripts'))
      FileUtils.cp(File.join(repo_root, 'scripts/build_ob_issues.rb'), File.join(@scratch, 'scripts'))
      File.symlink(File.join(repo_root, 'ituob'), File.join(@scratch, 'ituob'))
      @data = File.join(dir, 'itu-ob-data')
      @out = File.join(dir, 'ob-issues')
      seed_legacy(@data, [10, 11, 12])
      ex.run
    end
  end

  it 'with the cutover unset rewrites every edition from the legacy feed (unchanged behavior)' do
    write(File.join(@out, '12', 'e118-iin', '001-ADD.yaml'), "type: ADD\n")
    _o, err, st = run_build(@scratch, @data, @out)
    expect(st.success?).to be(true), err
    expect(File.exist?(File.join(@out, '12', 'e118-iin', '001-ADD.yaml'))).to be(false)
    expect(File.read(File.join(@out, '12', 'custom', '001.yaml'))).to include('legacy message 12')
    expect(File.exist?(File.join(@out, '12', 'zzz-test', 'text.yaml'))).to be(true)
  end

  it 'with the cutover unset and with an empty value produce identical output' do
    out_empty = "#{@out}-empty"
    run_build(@scratch, @data, @out)
    run_build(@scratch, @data, out_empty, 'CUTOVER_EDITION' => '')
    volatile = ['manifest.yaml']
    expect(tree(out_empty, except: volatile)).to eq(tree(@out, except: volatile))
    expect(manifest_stats).not_to have_key(:issues_preserved)
  end

  it 'never wipes or rewrites editions >= the cutover, and still rebuilds those below it' do
    submitted = File.join(@out, '11', 'e118-iin', '001-ADD.yaml')
    write(submitted, "type: ADD\nsubmitted: true\n")
    write(File.join(@out, '12', 'e118-iin', '003-ADD.yaml'), "type: ADD\nsubmitted: true\n")
    write(File.join(@out, '10', 'e118-iin', '001-ADD.yaml'), "type: ADD\nstale: true\n")
    before = tree(File.join(@out, '11')).merge(tree(File.join(@out, '12')).transform_keys { |k| "12/#{k}" })

    _o, err, st = run_build(@scratch, @data, @out, 'CUTOVER_EDITION' => '11')
    expect(st.success?).to be(true), err

    after = tree(File.join(@out, '11')).merge(tree(File.join(@out, '12')).transform_keys { |k| "12/#{k}" })
    expect(after).to eq(before)
    expect(File.exist?(File.join(@out, '11', 'custom', '001.yaml'))).to be(false)
    expect(File.exist?(File.join(@out, '10', 'e118-iin', '001-ADD.yaml'))).to be(false)
    expect(File.read(File.join(@out, '10', 'custom', '001.yaml'))).to include('legacy message 10')
    stats = manifest_stats
    expect(stats[:issues_preserved]).to eq(2)
    expect(stats[:issues_processed]).to eq(1)
  end

  it 'does not create an edition >= the cutover that the legacy feed has but the output lacks' do
    run_build(@scratch, @data, @out, 'CUTOVER_EDITION' => '12')
    expect(Dir.exist?(File.join(@out, '12'))).to be(false)
    expect(Dir.exist?(File.join(@out, '11'))).to be(true)
  end

  it 'rejects a non-numeric cutover' do
    _o, err, st = run_build(@scratch, @data, @out, 'CUTOVER_EDITION' => 'soon')
    expect(st.success?).to be(false)
    expect(err).to include('CUTOVER_EDITION must be a non-negative integer')
  end
end
