#!/usr/bin/env bash
# Stop hook shared by Claude Code (.claude/settings.json) and Codex (.codex/hooks.json):
# an agent can't finish a turn that left files changed while ./scripts/verify.sh fails.
# - No changed files: exit quietly (answering a question costs nothing).
# - stop_hook_active is true (already continued once because of this hook): let it stop.
#   The agent has seen the failure; the right move may be to ask a human.
# - Otherwise run verify; on failure, block with its last lines as the reason.
set -uo pipefail

input=$(cat)
root=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

if printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then exit 0; fi
[ -n "$(git status --porcelain)" ] || exit 0

if out=$(./scripts/verify.sh 2>&1); then exit 0; fi

reason="./scripts/verify.sh fails, so this task isn't done. Fix the cause and run it again. If the fix needs a human decision or would weaken a check, stop and explain that instead. Last lines of verify:
$(printf '%s\n' "$out" | tail -n 15)"
python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$reason"
