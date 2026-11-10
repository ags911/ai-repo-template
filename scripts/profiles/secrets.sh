#!/usr/bin/env bash
# Secrets profile: gitleaks over everything that changed since BASE_REF (committed,
# uncommitted, and new untracked files). GitHub's secret scanning needs a paid plan on
# private repos; this runs on any plan, before a key reaches main.
# gitleaks' own directory scan ignores .gitignore, so this feeds it what git sees instead.
set -euo pipefail
source .verify.env

fail() { echo "SECRETS PROFILE FAILED: $*" >&2; exit 1; }
command -v gitleaks >/dev/null || fail "gitleaks is not installed"

base="${BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$base" >/dev/null; then
  [ "${CI:-}" = "true" ] && fail "base ref '$base' not found in CI (fetch it with fetch-depth: 0)"
  echo "WARNING: base ref '$base' not found locally; scanning all tracked files"
  base=$(git hash-object -t tree /dev/null)
fi

{
  git diff "$base" -U0 | grep -E '^\+[^+]' || true
  git ls-files --others --exclude-standard -z | xargs -0 -r cat 2>/dev/null || true
} | gitleaks stdin --no-banner --redact --verbose --log-level warn \
  || fail "possible secret in the changes (shown redacted above)"
echo "ok"
