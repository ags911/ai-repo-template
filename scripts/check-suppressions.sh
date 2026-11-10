#!/usr/bin/env bash
# Heuristic guard against weakening checks. Flags, in the diff against BASE_REF:
#   - added suppressions or skipped/focused tests without a real reason on the same line:
#     a comment containing "reason:" plus at least three characters, or a Python
#     reason="..." argument (a "reason:" inside a test name doesn't count)
#   - deleted test files, or test files renamed to a non-test name, unless the old path is
#     listed in .verify-approvals (a CODEOWNERS-owned file, so adding a line needs review)
# It is a tripwire, not proof. CODEOWNERS review is the real control.
set -euo pipefail
source .verify.env
base="${BASE_REF:-origin/main}"

# The base must be an object that exists (a commit, or the empty tree on a first push).
# rev-parse --verify accepts any 40-hex string, so check the object itself.
if ! git cat-file -e "${base}^{tree}" 2>/dev/null; then
  if [ "${CI:-}" = "true" ]; then
    echo "SUPPRESSIONS FAILED: base ref '$base' not found in CI (fetch it with fetch-depth: 0)" >&2; exit 1
  fi
  echo "WARNING: base ref '$base' not found locally; suppression check skipped"; exit 0
fi

pattern='@ts-ignore|@ts-nocheck|@ts-expect-error|eslint-disable|gitleaks:allow|\.only\(|\.skip\(|\.todo\(|\bxit\(|\bxdescribe\(|\b(skip|todo|only): *true\b|# *type: *ignore|# *noqa|# *pyright: *ignore|pytest\.mark\.(skip|xfail)|pytest\.skip\('
reason='(#|//|/\*|--)[^"'"'"']*reason: *[^ ]{3,}|reason *= *["'"'"'][^"'"'"']{3,}'

excludes=(':(exclude)scripts/check-suppressions.sh' ':(exclude)*.md')
# --text and no diff drivers: a .gitattributes "-diff" or "binary" entry must not hide lines.
diff_opts=(--text --no-ext-diff --no-textconv)

# Tracked changes (committed, staged, or unstaged) relative to the base branch.
# Not wrapped in "|| true": if git diff itself fails, so does this check.
tracked_diff=$(git diff "${diff_opts[@]}" "$base" -U0 -- . "${excludes[@]}")
tracked=$(printf '%s\n' "$tracked_diff" | grep -E '^\+[^+]' || true)

# Untracked files are invisible to git diff, so read them directly (-a: as text).
untracked=$(git ls-files --others --exclude-standard -z -- . "${excludes[@]}" \
  | xargs -0 -r grep -aHnE "$pattern" 2>/dev/null | sed 's/^/+ /' || true)

added=$(printf '%s\n%s\n' "$tracked" "$untracked" \
  | grep -E "$pattern" | grep -vE "$reason" || true)

# Approved removals: one path per line in .verify-approvals; # starts a comment.
approved() {
  [ -f .verify-approvals ] || return 1
  sed 's/#.*//; s/[[:space:]]*$//' .verify-approvals | grep -qxF -- "$1"
}

# A test file by name or location. Anything under tests/ counts only with a code extension,
# so renaming tests/test_x.py to tests/test_x.py.bak is caught.
test_file='\.(test|spec)\.[cm]?[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$|(^|/)(tests?|__tests__)/.*\.(py|[cm]?[jt]sx?)$'
name_status=$(git diff "${diff_opts[@]}" "$base" -M --name-status --diff-filter=DR)
deleted=$(printf '%s\n' "$name_status" \
  | while IFS=$'\t' read -r st old new; do
      [ -n "${st:-}" ] || continue
      echo "$old" | grep -qE "$test_file" || continue
      approved "$old" && continue
      if [ "${st:0:1}" = D ]; then
        echo "$old"
      elif ! echo "$new" | grep -qE "$test_file"; then
        echo "$old -> $new"
      fi
    done || true)

status=0
if [ -n "$added" ]; then
  echo "SUPPRESSIONS FAILED: new suppressions/skips without 'reason:':" >&2
  echo "$added" >&2; status=1
fi
if [ -n "$deleted" ]; then
  echo "SUPPRESSIONS FAILED: test files deleted (needs human approval in .verify-approvals):" >&2
  echo "$deleted" >&2; status=1
fi
[ "$status" -eq 0 ] && echo "ok"
exit "$status"
