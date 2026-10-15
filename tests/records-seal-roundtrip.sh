#!/usr/bin/env bash
# Only an ephemeral key. Never reads the author's signing key or changes council files.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export OLYMPUS_COUNCIL_KEY="$scratch/key.json"
python3 "$repo_root/scripts/council-sign.py" keygen > "$scratch/public.txt"
digest=$(python3 -c 'import hashlib; print(hashlib.sha256(b"Test Person-Emberfall,1,1,0").hexdigest())')
request="RS1~1790000000~Emberfall+Emberfall2~Alliance~b~24318~1~$digest"
python3 "$repo_root/scripts/council-sign.py" seal "$request" > "$scratch/seal.txt"
luajit "$repo_root/tests/records-seal-roundtrip.lua" "$repo_root" "$scratch/public.txt" "$scratch/seal.txt"
if python3 "$repo_root/scripts/council-sign.py" seal 'RS1~1790000000~Emberfall+Emberfall2~Alliance~b~24399~5001~0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' >/dev/null 2>&1; then
  printf 'FAIL: out-of-bounds seal was signed\n' >&2
  exit 1
fi
