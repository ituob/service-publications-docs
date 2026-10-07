#!/usr/bin/env bash
# Backup the 18 corrupted source files before applying the fix.
set -euo pipefail

BACKUP="/Users/mulgogi/src/ituob/itu-ob-data/.backup-char-exploded-20260721"
mkdir -p "$BACKUP"

for iid in 1163 1164 1165 1166 1167 1168 1169 1170 1171 1172 1173 1174; do
  for f in amendments.yaml general.yaml; do
    src="/Users/mulgogi/src/ituob/itu-ob-data/issues/$iid/$f"
    if [ -f "$src" ]; then
      if grep -qE "^      '[0-9]+': " "$src"; then
        mkdir -p "$BACKUP/$iid"
        cp "$src" "$BACKUP/$iid/$f"
        echo "Backed up $iid/$f"
      fi
    fi
  done
done

echo "---"
echo "Total files backed up: $(find "$BACKUP" -type f | wc -l)"
