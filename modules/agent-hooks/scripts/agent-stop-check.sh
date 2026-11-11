#!/usr/bin/env bash
# Stop hook shared by Claude Code (.claude/settings.json) and Codex (.codex/hooks.json):
# an agent can't finish a turn while ./scripts/verify.sh fails on its work.
# - stop_hook_active is true (already sent back once by this hook): let it stop. The agent
#   has seen the failure; the right move may be to ask a human.
# - The repo is exactly as it was the last time verify passed: nothing to check.
# - Clean tree and HEAD already contained in the base branch: nothing to check.
# - Otherwise run verify (this catches work that was committed before stopping too). On a
#   pass, remember the state; on a failure, block with verify's last lines as the reason.
# Needs only bash and git.
set -uo pipefail

input=$(cat)

# The session's own folder (the input's "cwd"), so a Claude worktree is checked, not the
# original checkout; then CLAUDE_PROJECT_DIR; then the current directory.
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

if printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then exit 0; fi

# Fingerprint: HEAD, status, the tracked diff, and each untracked file by name and hash
# (hashing files one by one, so moving content between them changes the fingerprint).
state=$( { git rev-parse HEAD 2>/dev/null; git status --porcelain=v1 -uall
           git diff HEAD --binary 2>/dev/null
           git ls-files --others --exclude-standard -z \
             | while IFS= read -r -d '' f; do printf '%s %s\n' "$(git hash-object -- "$f")" "$f"; done
         } | git hash-object --stdin)
okfile=$(git rev-parse --git-path agent-stop-check.ok)
if [ -f "$okfile" ] && [ "$(cat "$okfile")" = "$state" ]; then exit 0; fi

if [ -z "$(git status --porcelain)" ]; then
  base=$(BASE_REF="${BASE_REF:-}"; [ -f .verify.env ] && . ./.verify.env >/dev/null 2>&1; echo "${BASE_REF:-origin/main}")
  # Skip only when the base exists and already contains HEAD. A missing base means we can't
  # tell what is new, so verify.
  if git cat-file -e "${base}^{commit}" 2>/dev/null && git merge-base --is-ancestor HEAD "$base"; then
    exit 0
  fi
fi

if out=$(./scripts/verify.sh 2>&1); then
  printf '%s' "$state" > "$okfile" 2>/dev/null || true
  exit 0
fi

reason="./scripts/verify.sh fails, so this task isn't done. Fix the cause and run it again. If the fix needs a human decision or would weaken a check, stop and explain that instead. Last lines of verify:
$(printf '%s\n' "$out" | tail -n 15)"
# JSON-encode in bash: drop control characters other than tab and newline, then escape.
esc=$(printf '%s' "$reason" | tr -d '\000-\010\013-\037' \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }')
printf '{"decision": "block", "reason": "%s"}\n' "$esc"
