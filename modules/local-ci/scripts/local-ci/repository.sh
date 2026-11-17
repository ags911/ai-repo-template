#!/usr/bin/env bash
# Shared profile scripts remain the authority; run extras once, then suppressions.
set -euo pipefail
source .verify.env
[ -n "${VERIFY_PROFILES// /}" ] || { echo 'VERIFY_PROFILES is empty' >&2; exit 1; }
for directory in ${REQUIRED_DIRS:-}; do
  [ -d "$directory" ] || { echo "Missing required directory: $directory" >&2; exit 1; }
done
for profile in $VERIFY_PROFILES; do
  case "$profile" in ts|python) continue ;; esac
  bash "scripts/profiles/$profile.sh"
done
bash scripts/check-suppressions.sh
