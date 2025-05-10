# LutaML Models for ITU Operational Bulletin

This directory contains dataset models created using the lutaml-model gem. These models are used to represent and manipulate dataset entries in a structured way.

## Base Models

- `Entry` - Base class for all dataset entries
- `Change` - Represents a change to a dataset (ADD, REP, SUP)
- `ChangeSet` - A collection of changes with metadata

## Dataset Models

- `X121A` - Data Country or Geographical Area Codes
- `E118` - Issuer Identifier Numbers for charge cards
- `M1400` - ITU Carrier Codes
- `E212` - Mobile Network Codes
- `Q708A` - Signalling Area/Network Codes


## Usage

### Loading Models

```ruby
require 'ituob'

# Load a dataset
dataset = Ituob::Dataset.new('path/to/dataset')

# Load models
models = dataset.load_models

# Access model attributes
models.each do |model|
  puts model.class
  # Access attributes based on model type
  puts model.code if model.respond_to?(:code)
  puts model.country_or_area if model.respond_to?(:country_or_area)
end
```

### Creating Models

```ruby
require 'ituob'

# Create a new model instance
x121a = Ituob::Models::X121A.new(
  code: "123",
  zone: "4",
  country_or_area: { "en" => "Example Country", "fr" => "Pays Exemple", "es" => "País Ejemplo" },
  reserved: false,
  spare: false
)

# Convert to hash
data = x121a.to_hash

# Create from ProseMirror-extracted data
data = { "code" => "123", "zone" => "4", "country_or_area" => "Example Country" }
model = Ituob::Models::X121A.from_prosemirror(data)
```

### Working with Changes

```ruby
require 'ituob'

# Create a change
change = Ituob::Models::Change.new(
  type: Ituob::Models::Change::ADD,
  identifier: { "code" => "123" },
  data: { "code" => "123", "zone" => "4", "country_or_area" => "Example Country" }
)

# Create a changeset
changeset = Ituob::Models::ChangeSet.new(
  date_requested: "2023-01-15",
  date_active: "2023-02-01",
  ob_issue_no: "1234",
  reference: "Reference/123",
  changes: [change]
)

# Apply a change to a dataset
dataset = Ituob::Dataset.new('path/to/dataset')
dataset.apply_change(change)
```
