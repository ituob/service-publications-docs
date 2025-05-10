# frozen_string_literal: true

module Ituob
  module Models
  end
end

require_relative 'models/multilingual_string'
require_relative 'models/change'
require_relative 'models/change_set'
require_relative 'models/entry'
require_relative 'models/amendment'

### IMPLEMENTED MODELS
require_relative 'models/e118_entry'
require_relative 'models/e118_action'
require_relative 'models/e118_amendment'

### TO BE IMPLEMENTED MODELS
require_relative 'models/e164b_entry'
require_relative 'models/e164d_entry'
require_relative 'models/e164d_note_n_entry'
require_relative 'models/e164d_note_o_entry'
require_relative 'models/e164d_note_pq_entry'

# A ProseMirror version of the OB Issue
require_relative 'models/old_issue'

# NOT IMPLEMENTED YET
# require_relative 'models/x121a'
# require_relative 'models/x121b'
# require_relative 'models/e180'
# require_relative 'models/e212'
# require_relative 'models/e212a'
# require_relative 'models/e212a_mccmnc'
# require_relative 'models/e212_et'
# require_relative 'models/e212_mcc_others'
# require_relative 'models/e212_shared_mcc'
# require_relative 'models/e218'

# require_relative 'models/f1'
# require_relative 'models/f400'
# require_relative 'models/f68'
# require_relative 'models/f68_a1'
# require_relative 'models/f68_a2'

# require_relative 'models/m1400'

# require_relative 'models/q708a'
# require_relative 'models/q708b'

# require_relative 'models/rr251'

# require_relative 'models/sr1'

# require_relative 'models/t35'
# require_relative 'models/t35b'

