# frozen_string_literal: true

module RegisterIntegrityFindings
  def write_change(name, hash)
    File.write(File.join(changes_dir, name), hash.to_yaml)
  end

  def change(type, code, data: nil, ob: 1001)
    { 'type' => type, 'register' => 'TEST', 'ob_issue_no' => ob, 'identifier' => { 'code' => code },
      'data' => data }.compact
  end

  def finding_errors
    result.errors.grep(/replay /)
  end

end
