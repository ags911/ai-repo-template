#!/usr/bin/env bash
# Compares the template release this project came from (the "Created from ai-repo-template
# vX.Y.Z" line in .verify.env) with a given release tag.
# Usage: scripts/template-update-check.sh LATEST_TAG   (e.g. v1.1.0)
# Prints current=..., latest=... and update=true|false. Exits 1 if either version is missing.
set -euo pipefail

latest="${1:-}"
current=$(grep -oE 'ai-repo-template v[0-9]+\.[0-9]+\.[0-9]+' .verify.env 2>/dev/null | head -n 1 | sed 's/.* v//' || true)
latest=${latest#v}

[ -n "$current" ] || { echo "template-update-check: no 'Created from ai-repo-template vX.Y.Z' line in .verify.env" >&2; exit 1; }
printf '%s' "$latest" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "template-update-check: latest tag '${1:-}' is not vX.Y.Z" >&2; exit 1; }

# Numeric comparison, field by field (no sort -V: it isn't on every platform).
newer=false
IFS=. read -r c1 c2 c3 <<< "$current"
IFS=. read -r l1 l2 l3 <<< "$latest"
if   [ "$l1" -ne "$c1" ]; then [ "$l1" -gt "$c1" ] && newer=true
elif [ "$l2" -ne "$c2" ]; then [ "$l2" -gt "$c2" ] && newer=true
elif [ "$l3" -gt "$c3" ]; then newer=true
fi

echo "current=v$current"
echo "latest=v$latest"
echo "update=$newer"
