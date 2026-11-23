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
# A stack profile is required by default, so a mistyped list ("tz") cannot pass by running
# only extras. A CI job that deliberately runs extras alone (for example links on a docs-only
# change) sets VERIFY_ALLOW_EXTRAS_ONLY=1; every named profile must still exist.
case " $VERIFY_PROFILES " in
  *" ts "*|*" python "*) ;;
  *)
    [ "${VERIFY_ALLOW_EXTRAS_ONLY:-0}" = 1 ] \
      || fail "VERIFY_PROFILES needs a stack profile (ts or python); secrets and links are extras (set VERIFY_ALLOW_EXTRAS_ONLY=1 to run extras alone)" ;;
esac

for d in ${REQUIRED_DIRS:-}; do
  [ -d "$d" ] || fail "required directory '$d' is missing; boundary checks would pass vacuously"
done

# Progress: one line per finished check with its time, so a long run is not silent.
# The "=== ... ===" lines below are matched by the selftest and quoted in PR descriptions.
read -ra profile_list <<< "$VERIFY_PROFILES"
total=$(( ${#profile_list[@]} + 1 ))   # the profiles, then the suppressions check
done_count=0

for p in $VERIFY_PROFILES; do
  script="scripts/profiles/$p.sh"
  [ -f "$script" ] || fail "unknown profile '$p' (no $script)"
  echo "=== profile: $p ==="
  started=$SECONDS
  bash "$script"
  done_count=$(( done_count + 1 ))
  echo "--- [$done_count/$total] $p passed in $(( SECONDS - started ))s"
done

echo "=== suppressions ==="
started=$SECONDS
bash scripts/check-suppressions.sh
done_count=$(( done_count + 1 ))
echo "--- [$done_count/$total] suppressions passed in $(( SECONDS - started ))s"

echo "--- verify took ${SECONDS}s in total"
echo "=== VERIFY PASSED ($VERIFY_PROFILES) ==="
