#!/usr/bin/env bash
# Secrets profile: gitleaks over everything that changed since BASE_REF (committed,
# uncommitted, and new untracked files). GitHub's secret scanning needs a paid plan on
# private repos; this runs on any plan, before a key reaches main.
# gitleaks' own directory scan ignores .gitignore, so this feeds it what git sees instead.
set -euo pipefail
source .verify.env

fail() { echo "SECRETS PROFILE FAILED: $*" >&2; exit 1; }
command -v gitleaks >/dev/null || fail "gitleaks is not installed"

empty_tree=$(git hash-object -t tree /dev/null)
base="${BASE_REF:-origin/main}"
# The base must exist as an object; rev-parse --verify accepts any 40-hex string.
if ! git cat-file -e "${base}^{tree}" 2>/dev/null; then
  [ "${CI:-}" = "true" ] && fail "base ref '$base' not found in CI (fetch it with fetch-depth: 0)"
  echo "WARNING: base ref '$base' not found locally; scanning all tracked files and history"
  base="$empty_tree"
fi

scan() { gitleaks "$@" --no-banner --redact --verbose --log-level warn; }

# 1. The end state: tracked changes since the base plus new untracked files. --text and no
#    diff drivers, so a .gitattributes "-diff" entry can't hide lines.
diff_out=$(git diff --text --no-ext-diff --no-textconv "$base" -U0)
{
  printf '%s\n' "$diff_out" | grep -E '^\+[^+]' || true
  git ls-files --others --exclude-standard -z | xargs -0 -r cat 2>/dev/null || true
} | scan stdin || fail "possible secret in the changes (shown redacted above)"

# 2. Every commit since the base: a secret added in one commit and removed in the next is
#    gone from the end state but still in the pushed history.
if [ -n "$(git rev-list -1 HEAD 2>/dev/null)" ]; then
  if [ "$base" = "$empty_tree" ]; then range="HEAD"; else range="$base..HEAD"; fi
  # --diff-merges=first-parent: a merge's own changes (e.g. made while resolving
  # conflicts) are shown too; git log hides them by default.
  scan git --log-opts="--text --diff-merges=first-parent $range" . || fail "possible secret in a commit since the base (shown redacted above)"
fi
echo "ok"
