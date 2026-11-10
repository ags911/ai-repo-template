#!/usr/bin/env bash
# Stop hook shared by Claude Code (.claude/settings.json) and Codex (.codex/hooks.json):
# an agent can't finish a turn while ./scripts/verify.sh fails on its work.
# - stop_hook_active is true (already sent back once by this hook): let it stop. The agent
#   has seen the failure; the right move may be to ask a human.
# - The repo is exactly as it was the last time verify passed: nothing to check.
# - Clean tree and no commits beyond the base branch: nothing to check.
# - Otherwise run verify (this catches work that was committed before stopping too). On a
#   pass, remember the state; on a failure, block with verify's last lines as the reason.
set -uo pipefail

input=$(cat)
root=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

if printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then exit 0; fi

# A fingerprint of HEAD, the working tree and untracked files.
state=$( { git rev-parse HEAD 2>/dev/null; git status --porcelain=v1 -uall
           git diff HEAD --binary 2>/dev/null
           git ls-files --others --exclude-standard -z | xargs -0 -r cat 2>/dev/null; } \
         | git hash-object --stdin)
okfile=$(git rev-parse --git-path agent-stop-check.ok)
if [ -f "$okfile" ] && [ "$(cat "$okfile")" = "$state" ]; then exit 0; fi

if [ -z "$(git status --porcelain)" ]; then
  base=$(BASE_REF="${BASE_REF:-}"; [ -f .verify.env ] && . ./.verify.env >/dev/null 2>&1; echo "${BASE_REF:-origin/main}")
  if ! git cat-file -e "${base}^{commit}" 2>/dev/null || git merge-base --is-ancestor HEAD "$base"; then
    exit 0
  fi
fi

if out=$(./scripts/verify.sh 2>&1); then
  printf '%s' "$state" > "$okfile" 2>/dev/null || true
  exit 0
fi

reason="./scripts/verify.sh fails, so this task isn't done. Fix the cause and run it again. If the fix needs a human decision or would weaken a check, stop and explain that instead. Last lines of verify:
$(printf '%s\n' "$out" | tail -n 15)"
python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$reason"
