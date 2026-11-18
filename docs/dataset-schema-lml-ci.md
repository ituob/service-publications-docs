# Dataset schema and instance gates

The owner of `datasets/*/schema-data.yaml`, `scripts/generate_data_schemas.rb`,
and `scripts/validate_data_lml.rb` is `ituob/service-publications-docs`.
At main `8f19d30c`, it tracks all 40 schemas and both scripts; the
`ituob/itu-ob-data` corpus tracks none of those paths. The ready-queue evidence
for ituob/ituob.github.io#100 identified 20 generated schemas, 20 hand-maintained
schemas, and no CI invocation validating the dataset seeds through LML classes.

All 40 datasets now have an Entry mapping in
`ituob/lib/ituob/ontology/data_schemas.yaml`. Property shapes come from
`messages.lml`; dataset constraints and descriptions remain in
`data_schema_overlays/*.yaml`. The remaining 20 schemas are generated, including
nullable fields, numeric/string tone frequencies and recursive RR.25.1 segments.
The complete seeds are checked against the generated schemas in focused specs.

The Test workflow runs two gates:

```sh
BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/generate_data_schemas.rb --verify
BUNDLE_GEMFILE=ituob/Gemfile bundle exec ruby scripts/validate_data_lml.rb --datasets-only
```

`--verify` compares the committed schema bytes to generated output without
writing files. It rejects missing, hand-edited, out-of-date and unmapped schemas,
and dataset seeds lacking a schema mapping. New schemas must also be tracked by
Git. To update schemas after editing their ontology or constraints, run the
generator without `--verify` and commit the resulting files.

`--datasets-only` discovers every `datasets/*/data.yaml`, resolves its Entry class
from the same ontology mapping, loads each row through that class, and checks
`validate`. It rejects unmapped datasets, non-array seeds, non-mapping rows,
model validation errors and an empty inventory. This preserves model coercion
and unknown-field handling; generated schema constraints have separate coverage.
Loading the parsed row directly also preserves YAML aliases in the recursive
RR.25.1 seed. Dataset schema validation retains explicitly supplied blank/null
fields after model serialization, including nested empty multilingual values;
this preserves required seed fields while ignoring unknown attributes. The
current corpus passes: **40 files, 19,368 entries**.

`ituob/spec/scripts/validate_dataset_lml_spec.rb` exercises the actual CLI in
temporary fixtures. A seed with `status: deliberately-bad-status` in
`1114-E.164D-Note-PQ/data.yaml` must exit 1 and report the filename, row and status
error; a valid `Assigned` entry must exit 0. A direct before/after reproduction
with the same bad seed showed the old main script exiting 0 after validating
zero files, and the new script exiting 1 with the invalid-status diagnostic.

The [46-row replay recheck](parity/replay-conflicts.md) records the separate
source/print verification and corrects the E.164 Note N/O/PQ seed claim.
