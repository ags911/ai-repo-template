#!/usr/bin/env bash
# Links profile: lychee checks every local link and #anchor in the repo's Markdown files.
# Offline: web links are skipped, so a website being down can't fail verify.
set -euo pipefail

fail() { echo "LINKS PROFILE FAILED: $*" >&2; exit 1; }
command -v lychee >/dev/null || fail "lychee is not installed"

files=()
while IFS= read -r -d '' f; do files+=("$f"); done \
  < <(git ls-files --cached --others --exclude-standard -z -- '*.md')
if [ "${#files[@]}" -eq 0 ]; then echo "no Markdown files"; exit 0; fi

lychee --offline --no-progress --include-fragments "${files[@]}" \
  || fail "broken links or anchors (see above)"
