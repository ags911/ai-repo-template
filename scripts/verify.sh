#!/usr/bin/env bash
# The one verification command. Runs locally and in CI. Every configured check must pass.
set -euo pipefail

# Repo root = parent of this script's real directory, following symlinks (e.g. ./verify).
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir=$(CDPATH='' cd -P "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
CDPATH='' cd -P "$(dirname "$src")/.."

fail() { echo "VERIFY FAILED: $*" >&2; exit 1; }

[ -f .verify.env ] || fail ".verify.env not found"
# shellcheck source=/dev/null
source .verify.env
[ -n "${VERIFY_PROFILES// /}" ] || fail "VERIFY_PROFILES is empty in .verify.env (set ts, python, or both)"
case " $VERIFY_PROFILES " in
  *" ts "*|*" python "*) ;;
  *) fail "VERIFY_PROFILES needs a stack profile (ts or python); secrets and links are extras" ;;
esac

for d in ${REQUIRED_DIRS:-}; do
  [ -d "$d" ] || fail "required directory '$d' is missing; boundary checks would pass vacuously"
done

for p in $VERIFY_PROFILES; do
  script="scripts/profiles/$p.sh"
  [ -f "$script" ] || fail "unknown profile '$p' (no $script)"
  echo "=== profile: $p ==="
  bash "$script"
done

echo "=== suppressions ==="
bash scripts/check-suppressions.sh

echo "=== VERIFY PASSED ($VERIFY_PROFILES) ==="
