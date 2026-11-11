#!/usr/bin/env bash
# ADR profile (adr module): docs/adr/ stays consistent as decisions pile up.
# - every ADR file is NNNN-short-title.md, with a unique number
# - its "- **Status:**" line is Proposed, Accepted, or "Superseded by ADR-NNNN"
# - a superseded ADR names a successor that exists
# - every ADR is listed in the index, docs/adr/README.md
# (The links profile checks the other direction: every index row points at a real file.)
set -euo pipefail

fail() { echo "ADR PROFILE FAILED: $*" >&2; exit 1; }
dir=docs/adr
[ -d "$dir" ] || fail "$dir not found"
[ -f "$dir/README.md" ] || fail "$dir/README.md (the index) not found"

problems=""
add() { problems="${problems}  $1"$'\n'; }
seen=" "

for f in "$dir"/*.md; do
  name=$(basename "$f")
  case "$name" in README.md|0000-template.md) continue ;; esac
  if ! printf '%s' "$name" | grep -Eq '^[0-9]{4}-[a-z0-9-]+\.md$'; then
    add "$name: name it NNNN-short-title.md"; continue
  fi
  num=${name%%-*}
  case "$seen" in *" $num "*) add "$name: number $num is used twice" ;; esac
  seen="$seen$num "

  status=$(sed -n 's/^- \*\*Status:\*\*[[:space:]]*//p' "$f" | head -n 1)
  if printf '%s' "$status" | grep -Eqx 'Proposed|Accepted'; then :
  elif printf '%s' "$status" | grep -Eqx 'Superseded by ADR-[0-9]{4}'; then
    succ=${status##*ADR-}
    ls "$dir/$succ"-*.md >/dev/null 2>&1 || add "$name: superseded by ADR-$succ, which doesn't exist"
  else
    add "$name: status '${status:-missing}' isn't Proposed, Accepted, or Superseded by ADR-NNNN"
  fi

  grep -Fq "($name)" "$dir/README.md" || add "$name: not listed in $dir/README.md"
done

[ -z "$problems" ] || fail $'\n'"$problems"
echo "ok"
