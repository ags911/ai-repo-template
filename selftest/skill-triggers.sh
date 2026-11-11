#!/usr/bin/env bash
# Manual check that the modules/skills skills load when they should, and not otherwise.
#
# Builds a scratch repo (core + selftest/ts-sample + the adr, architecture and skills
# modules), then runs one fresh headless Claude Code session per prompt and records which
# skill(s) the session loaded. File edits and shell are disabled in those sessions.
#
# Not run in CI: it needs a signed-in `claude` CLI and makes real model calls
# (one short session per prompt). Your own Claude Code settings and plugins are loaded,
# as they would be in real use.
#
# Usage: selftest/skill-triggers.sh [model]   (default: Claude Code's default model)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODEL="${1:-}"
command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/skill-triggers.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO"
cp -R "$ROOT/scripts" "$ROOT/.verify.env" "$ROOT/.gitignore" "$ROOT/AGENTS.md" "$REPO/"
(cd "$ROOT/selftest/ts-sample" && tar cf - --exclude node_modules .) | (cd "$REPO" && tar xf -)
for m in adr architecture skills; do cp -R "$ROOT/modules/$m/." "$REPO/"; done
(cd "$REPO" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid \
  -c commit.gpgsign=false commit -qm base)

# expected-skill|prompt   ("none" = no skill from this module should load)
CASES='adr-builder|We decided to switch payment status updates from polling to webhooks. Write this up as an ADR.
adr-builder|Record our decision to store orders in PostgreSQL rather than MongoDB.
adr-builder|Draft a decision record for moving session storage into Redis.
tradeoff-analyzer|Should we put a Redis cache in front of the orders API, or just add a database index?
tradeoff-analyzer|We are thinking about adding a GraphQL layer to the public API. What are our options?
tradeoff-analyzer|Is it worth adding a message queue between orders and billing, or should orders call billing directly?
fitness-function-generator|Enforce the layer rules in ARCHITECTURE.md in CI.
fitness-function-generator|Make the build fail if anything in src/domain imports from src/infrastructure.
fitness-function-generator|Set up dependency-cruiser rules that match our architecture.
quantum-evaluator|Our orders service and billing service share one Postgres database. Are they really independent?
quantum-evaluator|Should ARCHITECTURE.md use Profile A or Profile B for this system?
quantum-evaluator|How many independently deployable parts does this system actually have?
schema-migration-review|I want to rename the qty column on orders to quantity. Is that safe to do?
schema-migration-review|Plan how we change the order event payload so amount becomes amount_cents.
named-refactoring|placeOrder and createOrder are getting messy. Clean them up without changing behaviour.
named-refactoring|Untangle src/application/place-order.ts; it does too much in one function.
none|What does createOrder return when the quantity is 2?
none|Rename the variable repo to repository in src/application/place-order.ts.
none|Which npm scripts does this project define?'

OURS="adr-builder tradeoff-analyzer fitness-function-generator quantum-evaluator schema-migration-review named-refactoring"
pass=0; fail=0
printf '%-28s %-34s %s\n' "EXPECTED" "LOADED" "PROMPT"
while IFS='|' read -r want prompt; do
  [ -n "$want" ] || continue
  args=(-p "$prompt" --output-format stream-json --verbose --max-turns 4
        --disallowedTools "Bash Edit Write NotebookEdit")
  [ -n "$MODEL" ] && args+=(--model "$MODEL")
  out=$(cd "$REPO" && claude "${args[@]}" 2>/dev/null || true)
  # Skill names passed to the Skill tool in this session
  loaded=$(printf '%s\n' "$out" | node -e '
    const names = new Set();
    for (const line of require("fs").readFileSync(0, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let ev; try { ev = JSON.parse(line); } catch { continue; }
      for (const c of (ev.message && ev.message.content) || []) {
        if (c.type === "tool_use" && c.name === "Skill" && c.input) names.add(String(c.input.skill || c.input.command || ""));
      }
    }
    console.log([...names].join(",") || "-");
  ')
  ours=""
  for s in $OURS; do case ",$loaded," in *",$s,"*) ours="$ours $s" ;; esac; done
  ours="${ours# }"
  if { [ "$want" = none ] && [ -z "$ours" ]; } || { [ "$want" != none ] && [ "$ours" = "$want" ]; }; then
    pass=$((pass + 1)); mark=ok
  else
    fail=$((fail + 1)); mark=MISS
  fi
  printf '%-4s %-23s %-34s %s\n' "$mark" "$want" "$loaded" "$prompt"
done <<< "$CASES"

echo
echo "skill triggers: $pass ok, $fail missed (claude $(claude --version 2>/dev/null | head -1))"
[ "$fail" -eq 0 ]
