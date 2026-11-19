# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'

require File.expand_path('../../../scripts/compare_official_pdf', __dir__)

# Exercises the diff logic of scripts/compare_official_pdf.rb on small layout
# text fixtures (what `pdftotext -layout` prints); no PDF is read.
RSpec.describe OfficialPdfComparison do
  subject(:mod) { described_class }

  let(:generated_text) do
    <<~TXT
      Note from TSB

      a)  The new List replaces the old one.

      Country /      Network     Network   Name of     Office
      AFGHANISTAN                  AF- -   Kabul        AFKL
                                           All others   AFKX
      Annex to ITU OB No. 32-E        - 1 -
                                          Freeport Grand     BSFP
                                          Bahama
                                          Nassau Bahamas BSNU
      ÉMIRATS ARABES UNIS
    TXT
  end

  let(:official_text) do
    <<~TXT
      Note from TSB

      1.  The new  List replaces the old one.

      Country /geographical area   Network   Network code   Name of   Office code
      AFGHANISTAN        Kabul                  AF- -   Kabul        AFKL
      AFGHANISTAN                                       All others   AFKX
      Annex to ITU OB 980-E      - 2 -          15.V.2011
      BAHAMAS                                   Freeport Grand Bahama   BSFP
      BAHAMAS                                   Nassau Bahamas          BSNU
      BELARUS                                   All destinations        BYXX
      Geneva, 2011
    TXT
  end

  describe '.rows' do
    it 'keys rows on the 4-character office code and keeps the name cell' do
      expect(mod.rows(generated_text).map(&:to_s)).to eq(
        ['AFKL Kabul', 'AFKX All others', 'BSFP Freeport Grand', 'BSNU Nassau Bahamas']
      )
    end

    it 'ignores page furniture, a bare year and a country name ending in four capitals' do
      codes = mod.rows(official_text).map(&:code)
      expect(codes).to eq(%w[AFKL AFKX BSFP BSNU BYXX])
      expect(mod.rows("Geneva,   2011\nÉMIRATS ARABES UNIS\n")).to be_empty
    end

    it 'reads the form-feed-prefixed first line of a page and hyphen codes with footnote marks' do
      text = "\f                                              Nassau Bahamas BSNU\n" \
             "                              Antofagasta        --AF\n" \
             "                              All destinations   AAXX2)\n"
      expect(mod.rows(text).map(&:code)).to eq(%w[BSNU --AF AAXX])
    end
  end

  describe '.prose_words' do
    it 'covers the text between "Note from TSB" and the first table header, minus list markers' do
      expect(mod.prose_words(generated_text)).to eq(%w[Note from TSB The new List replaces the old one.])
      expect(mod.prose_words(official_text)).to eq(%w[Note from TSB The new List replaces the old one.])
    end
  end

  describe '.diff and .hunks' do
    it 'groups consecutive differences into one hunk each' do
      ops = mod.diff(%w[a b c d e], %w[a x y d f])
      expect(mod.hunks(ops)).to eq(
        [{ generated: %w[b c], official: %w[x y] }, { generated: %w[e], official: %w[f] }]
      )
    end

    it 'reports no hunk for equal sequences' do
      expect(mod.hunks(mod.diff(%w[a b], %w[a b]))).to be_empty
    end
  end

  describe '.run' do
    before do
      @tmp = Dir.mktmpdir
      File.write(File.join(@tmp, 'data.yaml'), [
        ['AFKL', 'Kabul'], ['AFKX', 'All others'], ['BSFP', 'Freeport Grand Bahama'],
        ['BSNU', 'Nassau Bahamas'], ['ZZ99', 'Never rendered']
      ].map { |c, n| { 'office_code' => c, 'telegraph_office_name' => { 'en' => n } } }.to_yaml)
      allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(generated_text)
      allow(mod).to receive(:pdf_text).with('off.pdf').and_return(official_text)
    end
    after { FileUtils.remove_entry(@tmp) }

    let(:result) { mod.run('gen.pdf', 'off.pdf', dataset: File.join(@tmp, 'data.yaml')) }

    it 'counts rows and matches' do
      expect(result[:counts]).to include(rows_generated: 4, rows_official: 5, rows_matched: 4)
    end

    it 'dispositions a wrapped name as layout, a row absent from the dataset as data, and an unrendered record as bug' do
      by_text = result[:deltas].to_h { |d| [d.text[/\A[^\s:]+/], d] }
      expect(by_text['BSFP']).to have_attributes(disposition: :layout, side: :both)
      expect(by_text['BYXX']).to have_attributes(disposition: :data, side: :official_only)
      expect(by_text['ZZ99']).to have_attributes(disposition: :bug, side: :dataset_only)
    end

    it 'sees no prose delta when only list markers and spacing differ' do
      expect(result[:deltas].select { |d| d.layer == :prose }).to be_empty
      expect(result[:counts]).to include(prose_words_generated: 10, prose_words_matched: 10)
    end

    it 'leaves a changed word for a human (unreviewed) and calls an unrelated name a bug' do
      changed = official_text.sub('the old one', 'the older list').sub('Nassau Bahamas', 'Hamilton')
      allow(mod).to receive(:pdf_text).with('off.pdf').and_return(changed)
      deltas = result[:deltas]
      expect(deltas.select { |d| d.layer == :prose }).to all(have_attributes(disposition: :unreviewed))
      expect(deltas.select { |d| d.layer == :prose }).not_to be_empty
      expect(deltas.find { |d| d.text.start_with?('BSNU') }).to have_attributes(disposition: :bug)
    end

    it 'prints a summary line with counts by disposition' do
      expect(mod.report(result)).to match(/deltas: 3 \{bug: 1, data: 1, layout: 1\}/)
    end
  end

  # The four ways the first pilot over-called "layout" or hid a bug (breaker
  # findings F1-F4 on spd#89). Rows are built the way pdftotext -layout prints
  # them: name cell, then the code.
  describe 'name, row and alignment rules' do
    def table(*pairs)
      rows = pairs.map do |name, code|
        next name if code.nil? # a continuation line, as is

        (' ' * 40) + name.to_s + (' ' * [24 - name.to_s.size, 2].max) + code.to_s
      end
      "Note from TSB\nCountry / Network   Name   Office\n#{rows.join("\n")}\n"
    end

    def deltas_for(generated, official, dataset: nil)
      allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(generated)
      allow(mod).to receive(:pdf_text).with('off.pdf').and_return(official)
      mod.run('gen.pdf', 'off.pdf', dataset: dataset)[:deltas].select { |d| d.layer == :rows }
    end

    let(:official) { table(['Rio de Janeiro', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE']) }

    describe 'F2: a name that gained or lost a word is not a wrap' do
      it 'calls an extended name a bug' do
        gen = table(['Rio de Janeiro Extra Wrong Tail', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, official)).to contain_exactly(
          have_attributes(side: :both, disposition: :bug, text: a_string_starting_with('BRRJ'))
        )
      end

      it 'calls a truncated name with no continuation line a bug' do
        gen = table(['Rio', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, official)).to contain_exactly(have_attributes(side: :both, disposition: :bug))
      end

      it 'keeps a real wrap (joined lines equal the other side) as layout' do
        gen = table(['Rio de', 'BRRJ'], ["#{' ' * 40}Janeiro"], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        off = table(['Rio de Janeiro', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, off)).to contain_exactly(have_attributes(side: :both, disposition: :layout))
      end

      it 'does not let a wrapped continuation excuse a different word' do
        gen = table(['Rio de', 'BRRJ'], ["#{' ' * 40}Sampa"], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, official)).to contain_exactly(have_attributes(disposition: :bug))
      end
    end

    describe 'F3: a generated-only row' do
      it 'is a bug when the official text does not contain it' do
        gen = table(['Rio de Janeiro', 'BRRJ'], ['Bogus Place', 'QQQQ'], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, official)).to contain_exactly(
          have_attributes(side: :generated_only, disposition: :bug, text: 'QQQQ Bogus Place')
        )
      end

      it 'is a bug when the official has the row elsewhere (duplicated or out of order)' do
        gen = table(['Rio de Janeiro', 'BRRJ'], ['Santos', 'BRSN'], ['Santos', 'BRSN'], ['Recife', 'BRRE'])
        expect(deltas_for(gen, official)).to contain_exactly(
          have_attributes(side: :generated_only, disposition: :bug)
        )
      end

      it 'is layout only when the official text carries it without it being a table row' do
        gen = table(['Rio de Janeiro', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE'], ['Total in', 'FOUR'])
        off = "#{official}Total in\nFOUR\n"
        expect(deltas_for(gen, off)).to contain_exactly(
          have_attributes(side: :generated_only, disposition: :layout)
        )
      end
    end

    describe 'F4: repeated codes align on code and name' do
      let(:run_of_rows) { %w[Agra Aligarh Allahabad Amritsar Bhopal].map { |n| [n, 'INNX'] } }

      it 'reports the dropped row, not the last one, and nothing else' do
        gen = table(*run_of_rows.reject { |n, _| n == 'Allahabad' })
        deltas = deltas_for(gen, table(*run_of_rows))
        expect(deltas).to contain_exactly(have_attributes(side: :official_only, text: 'INNX Allahabad'))
        expect(mod.run('gen.pdf', 'off.pdf')[:counts]).to include(rows_matched: 4)
      end

      it 'pairs a renamed row in the run by code instead of cascading' do
        gen = table(*run_of_rows.map { |n, c| [n == 'Allahabad' ? 'Prayagraj' : n, c] })
        expect(deltas_for(gen, table(*run_of_rows))).to contain_exactly(
          have_attributes(side: :both, disposition: :bug, text: a_string_including('Prayagraj'))
        )
      end
    end

    # Round-2 breaker findings: an entry pins the whole row, a wrap line belongs
    # to exactly one row, and a dropped line is a difference.
    describe 'wrap lines belong to exactly one row' do
      def wrap(text) = ["#{' ' * 40}#{text}", nil]

      let(:wrapped) do
        table(['Rio de', 'BRRJ'], wrap('Janeiro'), ['Santos', 'BRSN'], ['Recife', 'BRRE'])
      end

      it 'keeps a wrapped name equal to the unwrapped one as layout' do
        expect(deltas_for(wrapped, official)).to contain_exactly(have_attributes(disposition: :layout, side: :both))
      end

      it 'calls a dropped wrap line a bug, above, below or at the start of a block' do
        before = table(['Gamma', 'BBBB'], ['Republic of Foo', 'CCCC'])
        expect(deltas_for(table(['Republic of Foo', 'CCCC']), table(wrap('Gamma'), ['Republic of Foo', 'CCCC'])))
          .to contain_exactly(have_attributes(side: :both, disposition: :bug, text: a_string_including('"Gamma Republic of Foo"')))
        expect(deltas_for(table(['Gamma', 'BBBB']), table(['Gamma', 'BBBB'], wrap('Island Territory'))))
          .to contain_exactly(have_attributes(side: :both, disposition: :bug, text: a_string_including('"Gamma Island Territory"')))
        expect(deltas_for(before, before)).to be_empty
      end

      it 'calls a wrap line used by both neighbours a bug, and so one used by neither' do
        official_rows = table(['Alpha', 'AAAA'], wrap('Beta'), ['Gamma', 'BBBB'])
        doubled = table(['Alpha Beta', 'AAAA'], ['Beta Gamma', 'BBBB'])
        dropped = table(['Alpha', 'AAAA'], ['Gamma', 'BBBB'])
        expect(deltas_for(doubled, official_rows)).to include(have_attributes(side: :both, disposition: :bug))
        expect(deltas_for(dropped, official_rows)).to include(have_attributes(side: :both, disposition: :bug))
      end

      it 'accepts a single wrap line between two rows as either neighbour\'s when one split explains both PDFs' do
        # Undecidable from the text: the line is equally the tail of one row or
        # the head of the next (the real official PDF prints ALEXANDRIA / above
        # UNAA both ways). It counts once, so this is layout, not a bug.
        official_rows = table(['Alpha', 'AAAA'], wrap('Beta'), ['Gamma', 'BBBB'])
        generated_rows = table(['Alpha', 'AAAA'], ['Beta Gamma', 'BBBB'])
        expect(deltas_for(generated_rows, official_rows)).to all(have_attributes(disposition: :layout))
      end

      it 'reads a name line that shares the next row\'s code line as part of the wrapped name' do
        head = "Note from TSB\nCountry / Network   Name   Office\n"
        official_rows = "#{head}#{' ' * 40}Alpha,#{' ' * 40}AAAA\n" \
                        "#{' ' * 40}Ohio, USA#{' ' * 20}Delta#{' ' * 6}BBBB\n"
        generated = ->(name) { "#{head}#{' ' * 40}#{name}#{' ' * 20}AAAA\n#{' ' * 80}Delta#{' ' * 6}BBBB\n" }
        expect(deltas_for(generated.call('Alpha, Ohio, USA'), official_rows)).to all(have_attributes(disposition: :layout))
        expect(deltas_for(generated.call('Alpha, Iowa, USA'), official_rows))
          .to include(have_attributes(side: :both, disposition: :bug, text: a_string_including('Ohio, USA')))
      end
    end

    describe 'a disposition pins every fragment of the row, on both sides' do
      let(:entry_for) do
        lambda do |gen_text, off_text|
          { 'layer' => 'rows', 'side' => 'both', 'disposition' => 'layout', 'reason' => 'checked by eye',
            'text' => "BRRJ: generated #{gen_text.inspect} vs official #{off_text.inspect}" }
        end
      end

      def failures_with(gen, off, entry)
        allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(gen)
        allow(mod).to receive(:pdf_text).with('off.pdf').and_return(off)
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'd.yaml')
          File.write(file, [entry].to_yaml)
          mod.failures(mod.run('gen.pdf', 'off.pdf', dispositions: file))
        end
      end

      def wrap(text) = ["#{' ' * 40}#{text}", nil]

      let(:gen) { table(['Rio de Janeiro Extra', 'BRRJ'], wrap('Second Line'), ['Santos', 'BRSN']) }
      let(:off) { table(['Rio de Janeiro', 'BRRJ'], ['Santos', 'BRSN']) }
      let(:entry) { entry_for.call('Rio de Janeiro Extra Second Line', 'Rio de Janeiro') }

      it 'settles the row when both full texts match' do
        expect(failures_with(gen, off, entry)).to be_empty
      end

      it 'fails when a later generated fragment changes' do
        changed = gen.sub('Second Line', 'Other Line')
        expect(failures_with(changed, off, entry).join("\n")).to include('stale disposition').and include('Other Line')
      end

      it 'fails when a later official fragment changes' do
        changed_off = table(['Rio de Janeiro', 'BRRJ'], wrap('Springfield'), ['Santos', 'BRSN'])
        expect(failures_with(gen, changed_off, entry).join("\n")).to include('stale disposition').and include('Springfield')
      end
    end

    describe 'swapped rows with one code stay bugs' do
      it 'reports a swap of two same-code rows' do
        gen = table(['Beta', '--XX'], ['Alpha', '--XX'], ['Gamma', 'QQQQ'])
        off = table(['Alpha', '--XX'], ['Beta', '--XX'], ['Gamma', 'QQQQ'])
        expect(deltas_for(gen, off)).to include(have_attributes(side: :generated_only, disposition: :bug))
      end
    end

    describe 'usage and config errors exit 2 with a one-line message' do
      def main_status(*argv, dispositions: nil)
        Dir.mktmpdir do |dir|
          args = argv.dup
          if dispositions
            file = File.join(dir, 'd.yaml')
            File.write(file, dispositions)
            args += ['--dispositions', file]
          end
          status = nil
          err = StringIO.new
          $stderr = err
          begin
            status = mod.main(args)
          ensure
            $stderr = STDERR
          end
          [status, err.string]
        end
      end

      before do
        allow(mod).to receive(:pdf_text).and_return(official)
      end

      it 'rejects an unknown option' do
        status, err = main_status('gen.pdf', 'off.pdf', '--bogus')
        expect(status).to eq(2)
        expect(err.lines.size).to eq(1)
      end

      { 'an empty file' => '', 'a scalar list' => "- 5\n", 'a mapping' => "a: 1\n",
        'an entry without text' => "- layer: rows\n", 'invalid YAML' => "foo: [\n",
        'a non-integer count' => "- {layer: rows, side: both, text: x, count: two}\n" }.each do |label, body|
        it "rejects #{label} as a dispositions file" do
          status, err = main_status('gen.pdf', 'off.pdf', dispositions: body)
          expect(status).to eq(2)
          expect(err.lines.size).to eq(1)
        end
      end

      it 'rejects a missing dispositions file, dataset and PDF' do
        expect(main_status('gen.pdf', 'off.pdf', '--dispositions', '/nonexistent/d.yaml').first).to eq(2)
        expect(main_status('gen.pdf', 'off.pdf', '--data', '/nonexistent/data.yaml').first).to eq(2)
        allow(mod).to receive(:pdf_text).and_call_original
        status, err = main_status('/nonexistent/g.pdf', '/nonexistent/o.pdf')
        expect([status, err.lines.size]).to eq([2, 1])
      end
    end

    describe 'F1: dispositions come from a checked-in file and the exit status follows them' do
      let(:gen) { table(['Rio de Janeiro Extra', 'BRRJ'], ['Santos', 'BRSN'], ['Recife', 'BRRE']) }
      let(:entry) do
        { 'layer' => 'rows', 'side' => 'both', 'disposition' => 'layout', 'reason' => 'checked by eye',
          'text' => 'BRRJ: generated "Rio de Janeiro Extra" vs official "Rio de Janeiro"' }
      end

      def run_with(entries)
        allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(gen)
        allow(mod).to receive(:pdf_text).with('off.pdf').and_return(official)
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'dispositions.yaml')
          File.write(file, entries.to_yaml)
          mod.run('gen.pdf', 'off.pdf', dispositions: file)
        end
      end

      it 'fails (non-zero) with an open bug and no dispositions' do
        result = run_with([])
        expect(mod.failures(result).size).to eq(1)
        expect(mod.report(result)).to end_with('RESULT: FAIL (1 open)')
      end

      it 'passes when an entry settles it, and counts it in the tool output' do
        result = run_with([entry])
        expect(mod.failures(result)).to be_empty
        expect(result[:deltas]).to contain_exactly(have_attributes(disposition: :layout, manual: true))
        expect(mod.report(result)).to include('{layout: 1} (1 settled by the dispositions file)').and end_with('RESULT: PASS')
      end

      it 'fails on a stale entry, a reasonless entry and a wrong count' do
        stale = entry.merge('text' => 'BRRJ: generated "other" vs official "Rio de Janeiro"')
        expect(mod.failures(run_with([entry, stale])).join).to include('stale disposition')
        expect(mod.failures(run_with([entry.merge('reason' => ' ')])).join).to include('needs a reason')
        expect(mod.failures(run_with([entry.merge('count' => 2)])).join).to include('expected 2')
      end

      it 'exits 1 from main while a bug remains and 0 once it is dispositioned' do
        allow(mod).to receive(:pdf_text).with('gen.pdf').and_return(gen)
        allow(mod).to receive(:pdf_text).with('off.pdf').and_return(official)
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'd.yaml')
          File.write(file, [entry].to_yaml)
          expect { expect(mod.main(%w[gen.pdf off.pdf])).to eq(1) }.to output(/RESULT: FAIL/).to_stdout
          expect { expect(mod.main(['gen.pdf', 'off.pdf', '--dispositions', file])).to eq(0) }
            .to output(/RESULT: PASS/).to_stdout
        end
      end

      it 'ships a pilot doc with one Dispositions section and a dispositions file with reasons' do
        root = File.expand_path('../../..', __dir__)
        doc = File.read(File.join(root, 'docs/pdf/comparison-pilot.adoc'))
        expect(doc.scan(/^== Dispositions$/).size).to eq(1)
        entries = YAML.safe_load_file(File.join(root, 'docs/pdf/comparison-pilot-dispositions.yaml'))
        expect(entries).to all(include('reason' => a_string_matching(/\S/)))
      end
    end
  end

  describe 'shapes' do
    let(:shapes_dir) { File.expand_path('../../../scripts/official_pdf_shapes', __dir__) }

    it 'loads every file of scripts/official_pdf_shapes and finds F32' do
      expect(mod.shapes.keys).to include('F32')
      expect(Dir[File.join(shapes_dir, '*.rb')].map { |f| File.basename(f, '.rb') }).to include('base', 'f32')
    end

    it 'looks a shape up case-insensitively and names the known shapes on a miss' do
      expect(mod.shape('f32')).to be_a(OfficialPdfComparison::Shapes::F32)
      expect { mod.shape('nope') }.to raise_error(OfficialPdfComparison::UsageError, /unknown shape "nope".*F32/)
    end

    it 'gives every shape a PUBLICATIONS list of pub ids' do
      mod.shapes.each_value do |k|
        expect(k.publications).to all(match(/\AT-SP-/))
      end
      expect(mod.shapes['F32'].publications).to eq(%w[T-SP-F.32-2011])
    end

    it 'keeps the default shape for the F.32 rows API' do
      row = mod.rows("Kabul        AFKL\n").first
      expect([row.code, row.name]).to eq(%w[AFKL Kabul])
    end

    describe 'Base' do
      let(:klass) do
        Class.new(OfficialPdfComparison::Shapes::Base) do
          def rows(text) = text.lines.map { |l| OfficialPdfComparison::Shapes::Row.new(*l.split(': ', 2).map(&:strip)) }
        end
      end

      it 'requires a subclass to implement rows' do
        expect { OfficialPdfComparison::Shapes::Base.new.rows('') }.to raise_error(NotImplementedError)
      end

      it 'turns a generic Row into a comparable row' do
        a, b = klass.new.rows("X1: Alpha   Beta\nX1: alpha beta\n")
        expect([a.code, a.name, a.to_s]).to eq(['X1', 'Alpha   Beta', 'X1 Alpha   Beta'])
        expect(a.same_name?(b)).to be(true)
        expect(a.same_name?(OfficialPdfComparison::Shapes::Row.new('X1', 'Gamma'))).to be(false)
      end

      it 'runs a custom shape through the comparator without wrap logic' do
        shape = klass.new
        gen = shape.rows("A: one\nB: two\n")
        off = shape.rows("A: one\nB: 2\n")
        _eq, deltas = mod.compare_rows(gen, off)
        expect(deltas.map(&:disposition)).to eq([:bug])
        expect(deltas.first.text).to include('B').and include('two').and include('2')
      end
    end

    describe 'prose markers' do
      let(:markers) { { 'E' => 'Note from TSB', 'F' => 'Note du TSB', 'S' => 'Nota de la TSB' } }

      def text_for(marker) = "Preface before\n\n#{marker}\n\nfirst words here\n\nCountry / Network\n"

      it 'starts the preface at the language marker' do
        markers.each do |lang, marker|
          words = mod.prose_words(text_for(marker), lang: lang)
          expect(words).to eq(marker.split + %w[first words here])
        end
      end

      it 'does not start French or Spanish prose at the English marker' do
        expect(mod.prose_words(text_for('Note from TSB'), lang: 'F')).to include('Preface')
        expect(mod.prose_words(text_for('Note du TSB'), lang: 'E')).to include('Preface')
      end

      it 'reads the language from the official file name' do
        expect(mod.language_of('x/T-SP-F.32-2011-F.pdf')).to eq('F')
        expect(mod.language_of('T-SP-F.32-2011-S.pdf')).to eq('S')
        expect(mod.language_of('unnamed.pdf')).to eq('E')
      end
    end

    describe '--shape' do
      it 'rejects an unknown shape with exit 2 and runs a known one' do
        allow(mod).to receive(:pdf_text).and_return("Kabul        AFKL\n")
        expect { expect(mod.main(%w[g.pdf o.pdf --shape nope])).to eq(2) }.to output(/unknown shape/).to_stderr
        expect { expect(mod.main(%w[g.pdf o.pdf --shape F32])).to eq(0) }.to output(/RESULT: PASS/).to_stdout
      end

      it 'uses the --lang marker for the prose layer' do
        gen = "Note du TSB\n\nbonjour\n"
        off = "Intro\n\nNote du TSB\n\nbonjour\n"
        allow(mod).to receive(:pdf_text).with('g.pdf').and_return(gen)
        allow(mod).to receive(:pdf_text).with('o.pdf').and_return(off)
        expect { expect(mod.main(%w[g.pdf o.pdf --lang F])).to eq(0) }.to output(/prose_words_matched: 4/).to_stdout
      end
    end
  end
end
