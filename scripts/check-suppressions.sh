#!/usr/bin/env bash
# Heuristic guard against weakening checks. Flags, in the diff against BASE_REF:
#   - added suppressions or skipped/focused tests without "reason:" (or reason=) on the same line
#   - deleted test files, or test files renamed to a non-test name
# It is a tripwire, not proof. CODEOWNERS review is the real control.
set -euo pipefail
source .verify.env
base="${BASE_REF:-origin/main}"

if ! git rev-parse --verify --quiet "$base" >/dev/null; then
  if [ "${CI:-}" = "true" ]; then
    echo "SUPPRESSIONS FAILED: base ref '$base' not found in CI (fetch it with fetch-depth: 0)" >&2; exit 1
  fi
  echo "WARNING: base ref '$base' not found locally; suppression check skipped"; exit 0
fi

pattern='@ts-ignore|@ts-nocheck|@ts-expect-error|eslint-disable|\.only\(|\.skip\(|\bxit\(|\bxdescribe\(|# *type: *ignore|# *noqa|# *pyright: *ignore|pytest\.mark\.(skip|xfail)|pytest\.skip\('

excludes=(':(exclude)scripts/check-suppressions.sh' ':(exclude)*.md')

# Tracked changes (committed, staged, or unstaged) relative to the base branch
tracked=$(git diff "$base" -U0 -- . "${excludes[@]}" | grep -E '^\+[^+]' || true)

# Untracked files are invisible to git diff, so read them directly
untracked=$(git ls-files --others --exclude-standard -z -- . "${excludes[@]}" \
  | xargs -0 -r grep -HnE "$pattern" 2>/dev/null | sed 's/^/+ /' || true)

added=$(printf '%s\n%s\n' "$tracked" "$untracked" \
  | grep -E "$pattern" | grep -vE 'reason(:|=)' || true)

# Deleted test files, plus test files renamed to a non-test name (which hides them
# from the runner just as well). Moving a test to another test path is fine.
test_path='(^|/)(tests?|__tests__)/|\.(test|spec)\.[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$'
deleted=$(git diff "$base" -M --name-status --diff-filter=DR \
  | while IFS=$'\t' read -r st old new; do
      echo "$old" | grep -qE "$test_path" || continue
      if [ "$st" = D ]; then
        echo "$old"
      elif ! echo "$new" | grep -qE "$test_path"; then
        echo "$old -> $new"
      fi
    done || true)

status=0
if [ -n "$added" ]; then
  echo "SUPPRESSIONS FAILED: new suppressions/skips without 'reason:':" >&2
  echo "$added" >&2; status=1
fi
if [ -n "$deleted" ]; then
  echo "SUPPRESSIONS FAILED: test files deleted (needs human approval):" >&2
  echo "$deleted" >&2; status=1
fi
[ "$status" -eq 0 ] && echo "ok"
exit "$status"
