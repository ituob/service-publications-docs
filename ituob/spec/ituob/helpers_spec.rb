# frozen_string_literal: true

require 'spec_helper'
require 'ituob/helpers'

RSpec.describe Ituob::Helpers do
  NBSP = " "

  describe '.isolate_key' do
    it 'strips the "Key:" form and returns the value' do
      expect(described_class.isolate_key(['Name: Mr Kaya'], 'Name')).to eq('Mr Kaya')
    end

    it 'strips the "Key.:" form' do
      expect(described_class.isolate_key(['Tel.: +49 7252 960'], 'Tel')).to eq('+49 7252 960')
    end

    it 'matches the "E-mail:" printed form for the E-mail key' do
      expect(described_class.isolate_key(['E-mail: ckaya@enni.de'], 'E-mail')).to eq('ckaya@enni.de')
    end

    it 'finds the first matching line in a paragraph list' do
      lines = ['Mr Cafer Kaya', 'Tel:          +49 2841 104211', 'Fax: +49 2841 104384']
      expect(described_class.isolate_key(lines, 'Tel')).to eq('+49 2841 104211')
      expect(described_class.isolate_key(lines, 'Fax')).to eq('+49 2841 104384')
    end

    it 'normalizes non-breaking spaces inside the value' do
      expect(described_class.isolate_key(["Tel:#{NBSP}#{NBSP}+49 7252 960"], 'Tel')).to eq('+49 7252 960')
    end

    it 'returns nil when no line matches and for nil input' do
      expect(described_class.isolate_key(['Nothing here'], 'Tel')).to be_nil
      expect(described_class.isolate_key(nil, 'Tel')).to be_nil
    end
  end

  describe '.replace_legacy_space / .strip_legacy' do
    it 'replaces non-breaking spaces with plain spaces' do
      expect(described_class.replace_legacy_space("A#{NBSP}B")).to eq('A B')
    end

    it 'strips leading non-breaking space that String#strip misses' do
      expect("#{NBSP} Company Name/Address".strip).not_to eq('Company Name/Address')
      expect(described_class.strip_legacy("#{NBSP} Company Name/Address#{NBSP}")).to eq('Company Name/Address')
    end

    it 'handles nil like strip_legacy would' do
      expect(described_class.strip_legacy(nil)).to be_nil
    end
  end

  describe '.normalize_whitespace' do
    it 'collapses runs of spaces to single spaces and strips' do
      expect(described_class.normalize_whitespace('  P   47    Hungary   ')).to eq('P 47 Hungary')
    end

    it 'normalizes legacy non-breaking spaces BEFORE collapsing' do
      expect(described_class.normalize_whitespace("Tel:#{NBSP}#{NBSP}+49 7252  960 ")).to eq('Tel: +49 7252 960')
    end
  end

  describe '.remove_legacy_double_spaces' do
    it 'collapses runs of spaces into single spaces' do
      expect(described_class.remove_legacy_double_spaces('P  47    Hungary    ADD')).to eq('P 47 Hungary ADD')
    end
  end

  describe '.split_str family' do
    it 'split_str splits on any space kind' do
      expect(described_class.split_str("A#{NBSP}B  C")).to eq(%w[A B C])
    end

    it 'split_str_normal splits on single spaces' do
      expect(described_class.split_str_normal('A B')).to eq(%w[A B])
    end

    it 'split_str_normal_double splits on double-space runs' do
      expect(described_class.split_str_normal_double('A  B   C D')).to eq(['A', 'B', 'C D'])
    end
  end

  describe '.dump_table / .para_to_t / .dump_doc' do
    def doc_node(children)
      Prosereflect::Parser.parse_document({ 'type' => 'doc', 'content' => children })
    end

    def text_node(text)
      { 'type' => 'text', 'text' => text }
    end

    def hard_break
      { 'type' => 'hard_break' }
    end

    def table(*rows)
      { 'type' => 'table', 'content' =>
        rows.map do |cells|
          { 'type' => 'table_row', 'content' =>
            cells.map do |paras|
              { 'type' => 'table_cell', 'content' => paras }
            end }
        end }
    end

    it 'para_to_t returns the paragraph text nodes' do
      p = doc_node([{ 'type' => 'paragraph', 'content' => [text_node('A'), text_node('B')] }])
        .content.first
      expect(described_class.para_to_t(p)).to eq(%w[A B])
    end

    it 'dump_table joins each cell paragraph and keeps empty cells as [""]' do
      tbl = doc_node([table(
        [[{ 'type' => 'paragraph', 'content' => [text_node('ALLEMAGNE'), hard_break, text_node('GERMANY')] }],
         [{ 'type' => 'paragraph', 'content' => [text_node('DPXX')] }]],
        [[], []],
      )]).content.first
      dumped = described_class.dump_table(tbl)
      # hard_breaks contribute no text; words join with a single space.
      expect(dumped).to eq([[['ALLEMAGNE GERMANY'], ['DPXX']], [[''], ['']]])
    end

    it 'dump_table flattens NESTED tables inside cells' do
      cell_attrs = { 'type' => 'table_cell', 'attrs' => { 'colspan' => 1, 'rowspan' => 1, 'colwidth' => nil } }
      inner_row = {
        'type' => 'table_row',
        'content' => [
          cell_attrs.merge('content' => [{ 'type' => 'paragraph', 'content' => [text_node('105 K for range (a)')] }]),
        ],
      }
      nested = { 'type' => 'table', 'content' => [inner_row] }
      row = {
        'type' => 'table_row',
        'content' => [
          cell_attrs.merge('content' => [{ 'type' => 'paragraph', 'content' => [text_node('System noise temperature')] }]),
          cell_attrs.merge('content' => [nested]),
        ],
      }
      tbl = doc_node([{ 'type' => 'table', 'content' => [row] }]).content.first
      dumped = described_class.dump_table(tbl)

      expect(dumped.dig(0, 1).join(' ')).to include('105 K for range (a)')
    end

    it 'dump_doc walks paragraphs and tables in order' do
      d = doc_node([
        { 'type' => 'paragraph', 'content' => [text_node('P 1 TEST ADD')] },
        table([[{ 'type' => 'paragraph', 'content' => [text_node('X')] }]]),
      ])
      expect(described_class.dump_doc(d)).to eq([['P 1 TEST ADD'], [[['X']]]])
    end
  end

  describe '.grabcol2' do
    it 'returns the first paragraph of the second cell in the matching row' do
      rows = [
        [['Name of Administration:', ''], ['ITU', '']],
        [['Terminal Type:', ''], ['FAX', '']],
      ]
      expect(described_class.grabcol2(rows, 'Terminal Type')).to eq('FAX')
      expect(described_class.grabcol2(rows, 'Name of Administration')).to eq('ITU')
    end
  end
end
