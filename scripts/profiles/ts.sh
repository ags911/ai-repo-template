#!/usr/bin/env bash
# TypeScript profile. Requires package.json scripts: lint, typecheck, test.
# Runs "boundaries" too if defined. A missing required script is a failure, not a skip.
set -euo pipefail
source .verify.env
cd "${TS_DIR:-.}"

fail() { echo "TS PROFILE FAILED: $*" >&2; exit 1; }
[ -f package.json ] || fail "no package.json in '$PWD'"

if   [ -f pnpm-lock.yaml ]; then pm=pnpm
elif [ -f yarn.lock ];      then pm=yarn
else                             pm=npm
fi
command -v "$pm" >/dev/null || fail "$pm is not installed"

has_script() { node -e "process.exit(require('./package.json').scripts?.['$1'] ? 0 : 1)"; }

for s in lint typecheck test; do
  has_script "$s" || fail "package.json has no '$s' script"
  echo "--- $pm run $s"
  "$pm" run "$s"
done

if has_script boundaries; then
  echo "--- $pm run boundaries"
  "$pm" run boundaries
fi
