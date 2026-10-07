#!/usr/bin/env bash
# Restore the backup of corrupted source files.
set -euo pipefail

BACKUP="/Users/mulgogi/src/ituob/itu-ob-data/.backup-char-exploded-20260721"

for iid_dir in "$BACKUP"/*/; do
  iid=$(basename "$iid_dir")
  for f in "$iid_dir"/*.yaml; do
    fname=$(basename "$f")
    dst="/Users/mulgogi/src/ituob/itu-ob-data/issues/$iid/$fname"
    cp "$f" "$dst"
    echo "Restored $iid/$fname"
  done
done

echo "---"
echo "Verifying restoration..."
python3 -c "
import yaml
with open('/Users/mulgogi/src/ituob/itu-ob-data/issues/1163/amendments.yaml') as f:
    d = yaml.safe_load(f)
print('Parsed OK')
print('Messages:', len(d.get('messages', [])))
"
