#!/usr/bin/env bash
# Cases run in subshells on purpose (isolation); counts come back via files, not variables.
# shellcheck disable=SC2030,SC2031
# Self-test for the template's verification scripts.
#
# Builds throwaway git repos from this template (core scripts + selftest/ts-sample +
# modules/boundaries-ts), breaks them in specific ways, and asserts that
# scripts/verify.sh exits with the expected code AND fails for the expected reason.
# A case that fails for the wrong reason counts as a selftest failure.
#
# Usage: selftest/run.sh [case-name-substring]
# Needs: bash, git, node + npm (selftest/ts-sample/.nvmrc), and uv for the Python cases
# (selftest/py-sample). Installs the TS sample's node_modules with `npm ci` on first run;
# uv builds each Python scratch repo's environment from uv.lock (fast once cached).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SAMPLE="$ROOT/selftest/ts-sample"
PY_SAMPLE="$ROOT/selftest/py-sample"
FILTER="${1:-}"
# Every scratch repo lives under a path with a space in it, so quoting bugs fail every case.
WORK_BASE=$(mktemp -d "${TMPDIR:-/tmp}/verify-selftest.XXXXXX")
trap 'rm -rf "$WORK_BASE"' EXIT
WORK="$WORK_BASE/path with spaces"
mkdir -p "$WORK"

if [ ! -d "$SAMPLE/node_modules" ]; then
  echo "--- installing selftest/ts-sample dependencies"
  (cd "$SAMPLE" && npm ci --no-audit --no-fund)
fi

# Patterns that check-suppressions.sh looks for are split ("sk""ip") so this file
# never trips the check itself when a repo built from the template is verified.
TS_SKIP='test.sk''ip("pending", () => {});'
ES_DISABLE='// eslint-dis''able-next-line @typescript-eslint/no-explicit-any'
PY_SKIP='@pytest.mark.sk''ip'
PY_IGNORE='# type: ign''ore'

pass_count=0
fail_count=0
failures=""

# --- scratch repo helpers ----------------------------------------------------

# new_repo NAME: a committed repo on main (the TS sample wired up as a user would),
# with a "work" branch checked out. Prints nothing; cds into the repo.
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  cp -R "$ROOT/scripts" "$ROOT/.verify.env" "$ROOT/.gitignore" "$dir/"
  (cd "$SAMPLE" && tar cf - --exclude node_modules .) | (cd "$dir" && tar xf -)
  cp "$ROOT/modules/boundaries-ts/.dependency-cruiser.cjs" "$dir/"
  cp "$ROOT/modules/boundaries-ts/eslint.boundaries.js" "$dir/"
  ln -s "$SAMPLE/node_modules" "$dir/node_modules"
  cd "$dir"
  set_env VERIFY_PROFILES "ts"
  set_env REQUIRED_DIRS "src/domain src/application src/infrastructure"
  git init -q -b main
  git add -A
  commit "base"
  git checkout -q -b work
}

# commit MESSAGE [extra git-commit args]
# new_py_repo NAME: like new_repo, for selftest/py-sample wired to modules/boundaries-python.
new_py_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  cp -R "$ROOT/scripts" "$ROOT/.verify.env" "$ROOT/.gitignore" "$dir/"
  (cd "$PY_SAMPLE" && tar cf - --exclude .venv --exclude __pycache__ --exclude '.*_cache' .) \
    | (cd "$dir" && tar xf -)
  cp "$ROOT/modules/boundaries-python/.importlinter" "$dir/"
  cp "$ROOT/modules/boundaries-python/test_core_io.py" "$dir/tests/"
  cd "$dir"
  set_env VERIFY_PROFILES "python"
  set_env REQUIRED_DIRS "app/domain app/application app/infrastructure app/presentation"
  git init -q -b main
  git add -A
  commit "base"
  git checkout -q -b work
}

# py_probe FILE IMPORT_MODULE NAME: a lint- and type-clean module that imports NAME
py_probe() {
  printf 'from %s import %s\n\n__all__ = ["%s"]\n' "$2" "$3" "$3" > "$1"
}

commit() {
  local msg="$1"; shift
  git -c user.name=selftest -c user.email=selftest@example.invalid \
    -c commit.gpgsign=false commit -q --allow-empty -m "$msg" "$@"
}

# set_env KEY VALUE: rewrite KEY="..." in .verify.env, keeping any ${KEY:-default} form out
set_env() {
  local tmp
  tmp=$(mktemp)
  awk -v k="$1" -v v="$2" 'index($0, k "=") == 1 { print k "=\"" v "\""; next } { print }' \
    .verify.env > "$tmp"
  mv "$tmp" .verify.env
}

# set_script NAME COMMAND: set a package.json script ("" deletes it)
set_script() {
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
    if (process.argv[2]) p.scripts[process.argv[1]] = process.argv[2];
    else delete p.scripts[process.argv[1]];
    fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
  ' "$1" "$2"
}

# path_without TOOL: $PATH minus every directory that contains TOOL
path_without() {
  local out="" d
  local IFS=:
  for d in $PATH; do
    [ -x "$d/$1" ] && continue
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}

# --- assertions ----------------------------------------------------------------

# run_verify: run verify.sh with a known environment. Extra VAR=value args are passed to env.
run_verify() {
  env CI=false BASE_REF=main "$@" ./scripts/verify.sh > "$WORK/out.log" 2>&1
}

# expect NAME pass|fail "text that must appear in the output" [VAR=value ...]
expect() {
  local name="$1" want="$2" needle="$3"
  shift 3
  local rc=0
  run_verify "$@" || rc=$?
  local ok=1 why=""
  if [ "$want" = pass ] && [ "$rc" -ne 0 ]; then ok=0; why="expected exit 0, got $rc"; fi
  if [ "$want" = fail ] && [ "$rc" -eq 0 ]; then ok=0; why="expected non-zero exit, got 0"; fi
  if [ "$want" = fail ] && grep -q "VERIFY PASSED" "$WORK/out.log"; then ok=0; why="${why:+$why; }printed VERIFY PASSED"; fi
  if ! grep -qF -- "$needle" "$WORK/out.log"; then ok=0; why="${why:+$why; }output lacks: $needle"; fi
  report "$name" "$ok" "$why"
}

report() {
  if [ "$2" = 1 ]; then
    pass_count=$((pass_count + 1)); echo "ok   $1"
  else
    fail_count=$((fail_count + 1)); failures="$failures $1"
    echo "FAIL $1: $3"
    sed 's/^/     | /' "$WORK/out.log" | tail -25
  fi
}

want_case() { [ -z "$FILTER" ] || case "$1" in *"$FILTER"*) return 0 ;; *) return 1 ;; esac; }

# --- cases ---------------------------------------------------------------------

# Each case runs in its own subshell with errexit on, so a setup error aborts that case
# only. Counts are written to a file and summed by the main loop.
c() {
  local rc=0
  set +e
  ( set -e; pass_count=0; fail_count=0; failures=""; "case_$1" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ ! -f "$WORK/count.$1" ]; then
    echo "0 1 $1" > "$WORK/count.$1"; echo "FAIL $1: case setup errored (exit $rc)"
  fi
}
record() { echo "$pass_count $fail_count$failures" > "$WORK/count.$1"; }

case_empty_profiles() {
  new_repo empty_profiles; set_env VERIFY_PROFILES ""
  expect empty_profiles fail "VERIFY_PROFILES is empty"; record empty_profiles
}

case_unknown_profile() {
  new_repo unknown_profile; set_env VERIFY_PROFILES "ts go"
  expect unknown_profile fail "unknown profile 'go'"; record unknown_profile
}

case_missing_verify_env() {
  new_repo missing_verify_env; rm .verify.env
  expect missing_verify_env fail ".verify.env not found"; record missing_verify_env
}

case_missing_package_script() {
  new_repo missing_package_script; set_script typecheck ""
  expect missing_package_script fail "package.json has no 'typecheck' script"; record missing_package_script
}

case_missing_tool_pnpm() {
  new_repo missing_tool_pnpm; touch pnpm-lock.yaml
  expect missing_tool_pnpm fail "pnpm is not installed" PATH="$(path_without pnpm)"; record missing_tool_pnpm
}

case_missing_tool_uv() {
  new_repo missing_tool_uv; set_env VERIFY_PROFILES "python"
  printf '[project]\nname = "x"\nversion = "0"\n' > pyproject.toml; touch uv.lock
  expect missing_tool_uv fail "uv.lock present but uv is not installed" PATH="$(path_without uv)"; record missing_tool_uv
}

case_failing_lint_stops() {
  new_repo failing_lint_stops
  echo 'export const unused: any = 1;' > src/domain/bad.ts
  set_script typecheck "node -e \"require('fs').writeFileSync('.typecheck-ran','')\" && tsc --noEmit"
  expect failing_lint_stops fail "no-explicit-any"
  if [ -e .typecheck-ran ] || grep -q "=== suppressions" "$WORK/out.log"; then
    report failing_lint_stops_no_fallthrough 0 "a later step ran after lint failed"
  else
    report failing_lint_stops_no_fallthrough 1 ""
  fi
  record failing_lint_stops
}

case_failing_test_stops() {
  new_repo failing_test_stops
  sed -i.bak 's/quantity: 2 }/quantity: 3 }/' src/domain/order.test.ts && rm src/domain/order.test.ts.bak
  expect failing_test_stops fail "fail 1"; record failing_test_stops
}

case_missing_required_dir() {
  new_repo missing_required_dir; set_env REQUIRED_DIRS "src/domain src/presentation"
  expect missing_required_dir fail "required directory 'src/presentation' is missing"; record missing_required_dir
}

case_domain_imports_infrastructure() {
  new_repo domain_imports_infrastructure
  printf 'import { InMemoryOrderRepository } from "../infrastructure/in-memory-order-repository.ts";\nexport const repo = new InMemoryOrderRepository();\n' > src/domain/leak.ts
  expect domain_imports_infrastructure fail "domain-is-pure"; record domain_imports_infrastructure
}

case_domain_type_import_infrastructure() {
  new_repo domain_type_import_infrastructure
  printf 'import type { InMemoryOrderRepository } from "../infrastructure/in-memory-order-repository.ts";\nexport type Repo = InMemoryOrderRepository;\n' > src/domain/leak.ts
  expect domain_type_import_infrastructure fail "domain-is-pure"; record domain_type_import_infrastructure
}

case_skip_without_reason() {
  # .verify.env keeps its default BASE_REF; the env var must win (CI sets it per event).
  new_repo skip_without_reason
  printf 'import { test } from "node:test";\n%s\n' "$TS_SKIP" > src/domain/pending.test.ts
  git add -A; commit "add skip"
  expect skip_without_reason fail "without 'reason:'"; record skip_without_reason
}

case_skip_with_reason() {
  new_repo skip_with_reason
  printf 'import { test } from "node:test";\n%s // reason: blocked on upstream fix\n' "$TS_SKIP" > src/domain/pending.test.ts
  git add -A; commit "add skip with reason"
  expect skip_with_reason pass "VERIFY PASSED"; record skip_with_reason
}

case_suppression_without_reason() {
  new_repo suppression_without_reason
  printf '%s\nexport const legacy: any = 1;\n' "$ES_DISABLE" > src/domain/legacy.ts
  expect suppression_without_reason fail "without 'reason:'"; record suppression_without_reason
}

case_suppression_with_reason() {
  new_repo suppression_with_reason
  printf '%s -- reason: third-party type is untyped\nexport const legacy: any = 1;\n' "$ES_DISABLE" > src/domain/legacy.ts
  git add -A
  expect suppression_with_reason pass "VERIFY PASSED"; record suppression_with_reason
}

case_python_skip_without_reason() {
  new_repo python_skip_without_reason
  printf 'import pytest\n\n%s\ndef test_x():\n    pass\n' "$PY_SKIP" > test_x.py
  git add -A
  expect python_skip_without_reason fail "without 'reason:'"; record python_skip_without_reason
}

case_python_skip_with_reason_equals() {
  new_repo python_skip_with_reason_equals
  printf 'import pytest\n\n%s(reason="needs a live database")\ndef test_x():\n    pass\n' "$PY_SKIP" > test_x.py
  git add -A
  expect python_skip_with_reason_equals pass "VERIFY PASSED"; record python_skip_with_reason_equals
}

case_python_ignore_without_reason() {
  new_repo python_ignore_without_reason
  printf 'x: int = "a"  %s\n' "$PY_IGNORE" > mod.py
  git add -A
  expect python_ignore_without_reason fail "without 'reason:'"; record python_ignore_without_reason
}

case_python_ignore_with_reason() {
  new_repo python_ignore_with_reason
  printf 'x: int = "a"  %s  # reason: stub package is wrong\n' "$PY_IGNORE" > mod.py
  git add -A
  expect python_ignore_with_reason pass "VERIFY PASSED"; record python_ignore_with_reason
}

case_untracked_file_with_skip() {
  new_repo untracked_file_with_skip
  printf 'import { test } from "node:test";\n%s\n' "$TS_SKIP" > src/domain/untracked.test.ts
  expect untracked_file_with_skip fail "untracked.test.ts"; record untracked_file_with_skip
}

case_untracked_file_with_skip_reason() {
  new_repo untracked_file_with_skip_reason
  printf 'import { test } from "node:test";\n%s // reason: tracked in issue 12\n' "$TS_SKIP" > src/domain/untracked.test.ts
  expect untracked_file_with_skip_reason pass "VERIFY PASSED"; record untracked_file_with_skip_reason
}

case_deleted_test_committed() {
  new_repo deleted_test_committed
  git rm -q src/domain/order.test.ts; commit "drop test"
  expect deleted_test_committed fail "test files deleted"; record deleted_test_committed
}

case_deleted_test_uncommitted() {
  new_repo deleted_test_uncommitted
  rm src/domain/order.test.ts
  expect deleted_test_uncommitted fail "test files deleted"; record deleted_test_uncommitted
}

case_test_renamed_to_non_test() {
  new_repo test_renamed_to_non_test
  git mv src/domain/order.test.ts src/domain/order.test.ts.bak; commit "hide test"
  expect test_renamed_to_non_test fail "test files deleted"; record test_renamed_to_non_test
}

case_test_moved_stays_test() {
  # Moving a test to another test path is not a deletion.
  new_repo test_moved_stays_test
  git mv src/domain/order.test.ts src/domain/order-rules.test.ts; commit "rename test"
  expect test_moved_stays_test pass "VERIFY PASSED"; record test_moved_stays_test
}

case_base_missing_in_ci() {
  new_repo base_missing_in_ci
  expect base_missing_in_ci fail "not found in CI" CI=true BASE_REF=origin/nope; record base_missing_in_ci
}

case_base_missing_locally_warns() {
  new_repo base_missing_locally_warns
  expect base_missing_locally_warns pass "suppression check skipped" BASE_REF=origin/nope; record base_missing_locally_warns
}

case_ci_base_ref() {
  # scripts/ci-base-ref.sh picks the diff base for each CI event.
  new_repo ci_base_ref
  local first empty got ok=1 why=""
  first=$(git rev-parse HEAD); commit "second"
  empty=$(git hash-object -t tree /dev/null)
  : > "$WORK/out.log"
  got=$(EVENT=pull_request PR_BASE=main BEFORE="" scripts/ci-base-ref.sh)
  [ "$got" = "origin/main" ] || { ok=0; why="pull_request gave '$got'"; }
  got=$(EVENT=push PR_BASE="" BEFORE="$first" scripts/ci-base-ref.sh)
  [ "$got" = "$first" ] || { ok=0; why="$why push gave '$got'"; }
  got=$(EVENT=push PR_BASE="" BEFORE=0000000000000000000000000000000000000000 scripts/ci-base-ref.sh)
  [ "$got" = "$empty" ] || { ok=0; why="$why first push gave '$got'"; }
  report ci_base_ref "$ok" "$why"; record ci_base_ref
}

case_first_push_clean() {
  # First push to main: no previous commit, so the base is the empty tree and the
  # whole initial content is checked.
  new_repo first_push_clean; git checkout -q main; git branch -q -D work
  expect first_push_clean pass "VERIFY PASSED" \
    BASE_REF="$(EVENT=push BEFORE=0000000000000000000000000000000000000000 scripts/ci-base-ref.sh)"
  record first_push_clean
}

case_first_push_with_skip() {
  new_repo first_push_with_skip; git checkout -q main; git branch -q -D work
  printf 'import { test } from "node:test";\n%s\n' "$TS_SKIP" > src/domain/pending.test.ts
  git add -A; commit "base" --amend
  expect first_push_with_skip fail "without 'reason:'" \
    BASE_REF="$(EVENT=push BEFORE=0000000000000000000000000000000000000000 scripts/ci-base-ref.sh)"
  record first_push_with_skip
}

case_clean_pass() {
  new_repo clean_pass
  printf 'export function total(quantities: number[]): number {\n  return quantities.reduce((a, b) => a + b, 0);\n}\n' > src/domain/total.ts
  git add -A; commit "add total"
  expect clean_pass pass "=== VERIFY PASSED (ts) ==="; record clean_pass
}

case_skills_frontmatter() {
  # Each SKILL.md opens with YAML frontmatter whose name matches its directory and whose
  # description is present and within Claude Code's 1,536-character listing limit.
  local f dir ok=1 why=""
  : > "$WORK/out.log"
  for f in "$ROOT"/modules/skills/.agents/skills/*/SKILL.md; do
    dir=$(basename "$(dirname "$f")")
    awk -v want="$dir" '
      NR == 1 { if ($0 != "---") { print "first line is not ---"; bad = 1 }; next }
      !closed && $0 == "---" { closed = 1; next }
      !closed && /^name: / { name = substr($0, 7) }
      !closed && /^description: / { desc = substr($0, 14) }
      END {
        if (!closed) { print "frontmatter not closed"; bad = 1 }
        if (name != want) { print "name \"" name "\" does not match directory"; bad = 1 }
        if (length(desc) == 0) { print "no description"; bad = 1 }
        if (length(desc) > 1536) { print "description over 1536 chars"; bad = 1 }
        exit bad
      }' "$f" >> "$WORK/out.log" || { ok=0; why="$why $dir"; }
  done
  [ -n "${f:-}" ] && [ -f "$f" ] || { ok=0; why="no skills found"; }
  report skills_frontmatter "$ok" "bad frontmatter:$why"; record skills_frontmatter
}

# Workflow lint: the same pinned tools as selftest.yml, on a copy of the workflows.
ACTIONLINT="uvx --from actionlint-py==1.7.12.25 actionlint -no-color"
ZIZMOR="uvx zizmor==1.32.0 --offline"

case_workflows_lint_clean() {
  local dir="$WORK/workflows_lint_clean"
  mkdir -p "$dir"; cp -R "$ROOT/.github" "$dir/"; cd "$dir"; git init -q
  set +e; { $ACTIONLINT && $ZIZMOR .github/workflows; } > "$WORK/out.log" 2>&1; local rc=$?; set -e
  if [ "$rc" -eq 0 ]; then report workflows_lint_clean 1 ""; else report workflows_lint_clean 0 "workflow lint failed on the template's own workflows"; fi
  record workflows_lint_clean
}

case_workflows_lint_catches_bad_expression() {
  local dir="$WORK/workflows_lint_bad"
  mkdir -p "$dir"; cp -R "$ROOT/.github" "$dir/"; cd "$dir"; git init -q
  # A typo in a context name: valid YAML, so only an expression-aware linter sees it.
  sed -i.bak 's/steps.cfg.outputs.ts_dir/steps.cgf.outputs.ts_dir/' .github/workflows/verify.yml
  rm .github/workflows/verify.yml.bak
  set +e; $ACTIONLINT > "$WORK/out.log" 2>&1; local rc=$?; set -e
  if [ "$rc" -ne 0 ] && grep -q 'cgf' "$WORK/out.log"; then report workflows_lint_catches_bad_expression 1 ""
  else report workflows_lint_catches_bad_expression 0 "actionlint did not flag the bad expression (exit $rc)"; fi
  record workflows_lint_catches_bad_expression
}

case_workflows_lint_catches_injection() {
  local dir="$WORK/workflows_lint_injection"
  mkdir -p "$dir"; cp -R "$ROOT/.github" "$dir/"; cd "$dir"; git init -q
  # A PR title interpolated straight into a shell script: the classic injection.
  cat >> .github/workflows/verify.yml <<'EOF'
      - name: Echo the title
        run: echo "${{ github.event.pull_request.title }}"
EOF
  set +e; $ZIZMOR .github/workflows > "$WORK/out.log" 2>&1; local rc=$?; set -e
  if [ "$rc" -ne 0 ] && grep -q 'template-injection' "$WORK/out.log"; then report workflows_lint_catches_injection 1 ""
  else report workflows_lint_catches_injection 0 "zizmor did not flag the injection (exit $rc)"; fi
  record workflows_lint_catches_injection
}

case_skills_linked() {
  # Skills live in .agents/skills (Codex reads it); Claude Code reads only .claude/skills,
  # so each skill needs a relative symlink there, and each symlink needs a skill.
  local d n link ok=1 why=""
  : > "$WORK/out.log"
  for d in "$ROOT"/modules/skills/.agents/skills/*/; do
    n=$(basename "$d"); link="$ROOT/modules/skills/.claude/skills/$n"
    if [ ! -L "$link" ] || [ "$(readlink "$link")" != "../../.agents/skills/$n" ]; then
      ok=0; why="$why $n(no link)"
    fi
  done
  for link in "$ROOT"/modules/skills/.claude/skills/*; do
    [ -f "$link/SKILL.md" ] || { ok=0; why="$why $(basename "$link")(dangling)"; }
  done
  report skills_linked "$ok" "skill links wrong:$why"; record skills_linked
}

case_py_clean_pass() {
  new_py_repo py_clean_pass
  expect py_clean_pass pass "=== VERIFY PASSED (python) ==="
  if grep -q "Contracts: 6 kept, 0 broken" "$WORK/out.log"; then
    report py_clean_pass_contracts_ran 1 ""
  else
    report py_clean_pass_contracts_ran 0 "lint-imports did not report 6 kept contracts"
  fi
  record py_clean_pass
}

case_py_domain_imports_infrastructure() {
  new_py_repo py_domain_imports_infrastructure
  py_probe app/domain/leak.py app.infrastructure.in_memory_order_repository InMemoryOrderRepository
  expect py_domain_imports_infrastructure fail "Domain does not import infrastructure BROKEN"
  record py_domain_imports_infrastructure
}

case_py_application_imports_infrastructure() {
  new_py_repo py_application_imports_infrastructure
  py_probe app/application/leak.py app.infrastructure.in_memory_order_repository InMemoryOrderRepository
  expect py_application_imports_infrastructure fail "Application does not import infrastructure BROKEN"
  record py_application_imports_infrastructure
}

case_py_presentation_imports_infrastructure() {
  new_py_repo py_presentation_imports_infrastructure
  py_probe app/presentation/leak.py app.infrastructure.in_memory_order_repository InMemoryOrderRepository
  expect py_presentation_imports_infrastructure fail "Presentation does not import infrastructure BROKEN"
  record py_presentation_imports_infrastructure
}

case_py_domain_imports_application() {
  new_py_repo py_domain_imports_application
  py_probe app/domain/leak.py app.application.place_order place_order
  expect py_domain_imports_application fail "Layer rules from ARCHITECTURE.md BROKEN"
  record py_domain_imports_application
}

case_py_failing_ruff_stops() {
  new_py_repo py_failing_ruff_stops
  printf 'import os\n' > app/domain/unused.py
  expect py_failing_ruff_stops fail "F401"
  if grep -q -- "--- mypy" "$WORK/out.log"; then
    report py_failing_ruff_stops_no_fallthrough 0 "mypy ran after ruff failed"
  else
    report py_failing_ruff_stops_no_fallthrough 1 ""
  fi
  record py_failing_ruff_stops
}

case_py_type_error() {
  new_py_repo py_type_error
  printf 'count: int = "three"\n' > app/domain/bad.py
  expect py_type_error fail "Incompatible types in assignment"; record py_type_error
}

case_py_no_tests_fails() {
  # Tests absent from the start (so the deleted-test check is not what fails).
  new_py_repo py_no_tests_fails
  git checkout -q main; git rm -q tests/test_orders.py tests/test_core_io.py; commit "base" --amend; git checkout -q -B work main
  expect py_no_tests_fails fail "pytest collected no tests"; record py_no_tests_fails
}

case_py_no_tests_allowed_while_bootstrapping() {
  new_py_repo py_no_tests_allowed_while_bootstrapping
  git checkout -q main; git rm -q tests/test_orders.py tests/test_core_io.py; commit "base" --amend; git checkout -q -B work main
  set_env ALLOW_EMPTY_TESTS 1
  expect py_no_tests_allowed_while_bootstrapping pass "WARNING: no tests collected"
  record py_no_tests_allowed_while_bootstrapping
}

case_run_from_subdirectory() {
  new_repo run_from_subdirectory
  local rc=0
  (cd src/domain && env CI=false BASE_REF=main ../../scripts/verify.sh) > "$WORK/out.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q "VERIFY PASSED" "$WORK/out.log"; then
    report run_from_subdirectory 1 ""
  else
    report run_from_subdirectory 0 "exit $rc when run from src/domain"
  fi
  record run_from_subdirectory
}

case_run_from_outside_repo() {
  new_repo run_from_outside_repo
  local repo rc=0
  repo=$PWD
  (cd "$WORK_BASE" && env CI=false BASE_REF=main "$repo/scripts/verify.sh") > "$WORK/out.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q "VERIFY PASSED" "$WORK/out.log"; then
    report run_from_outside_repo 1 ""
  else
    report run_from_outside_repo 0 "exit $rc when run by absolute path from another directory"
  fi
  record run_from_outside_repo
}

case_run_through_symlink() {
  # A convenience link at the repo root (./verify -> scripts/verify.sh) must still find the root.
  new_repo run_through_symlink
  ln -s scripts/verify.sh verify
  echo verify >> .git/info/exclude
  local rc=0
  env CI=false BASE_REF=main ./verify > "$WORK/out.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q "VERIFY PASSED" "$WORK/out.log"; then
    report run_through_symlink 1 ""
  else
    report run_through_symlink 0 "exit $rc when run through a symlink"
  fi
  record run_through_symlink
}

case_domain_reaches_infrastructure_via_barrel() {
  # domain -> shared/index.ts -> infrastructure: no direct import, still a leak.
  new_repo domain_reaches_infrastructure_via_barrel
  mkdir -p src/shared
  printf 'export { InMemoryOrderRepository } from "../infrastructure/in-memory-order-repository.ts";\n' > src/shared/index.ts
  printf 'import { InMemoryOrderRepository } from "../shared/index.ts";\nexport const repo = new InMemoryOrderRepository();\n' > src/domain/leak.ts
  expect domain_reaches_infrastructure_via_barrel fail "domain-not-reach-infrastructure"
  record domain_reaches_infrastructure_via_barrel
}

case_domain_imports_infrastructure_via_alias() {
  new_repo domain_imports_infrastructure_via_alias
  node -e '
    const fs = require("fs");
    const t = JSON.parse(fs.readFileSync("tsconfig.json", "utf8"));
    t.compilerOptions.paths = { "@infra/*": ["./src/infrastructure/*"] };
    fs.writeFileSync("tsconfig.json", JSON.stringify(t, null, 2) + "\n");
  '
  printf 'import { InMemoryOrderRepository } from "@infra/in-memory-order-repository.ts";\nexport const repo = new InMemoryOrderRepository();\n' > src/domain/leak.ts
  expect domain_imports_infrastructure_via_alias fail "domain-is-pure"
  record domain_imports_infrastructure_via_alias
}

# with_fake_package NAME: replace the node_modules symlink with a real directory of links
# to the sample's packages, plus a minimal typed package NAME.
with_fake_package() {
  local e
  rm node_modules; mkdir node_modules
  for e in "$SAMPLE"/node_modules/* "$SAMPLE"/node_modules/.bin; do ln -s "$e" "node_modules/$(basename "$e")"; done
  mkdir -p "node_modules/$1"
  printf '{ "name": "%s", "version": "1.0.0", "main": "index.js", "types": "index.d.ts" }\n' "$1" > "node_modules/$1/package.json"
  printf 'export class Client {}\n' > "node_modules/$1/index.js"
  printf 'export declare class Client {}\n' > "node_modules/$1/index.d.ts"
}

case_domain_imports_infra_package() {
  new_repo domain_imports_infra_package; with_fake_package pg
  printf 'import { Client } from "pg";\nexport const db = new Client();\n' > src/domain/leak.ts
  expect domain_imports_infra_package fail "core-no-infra-packages"
  record domain_imports_infra_package
}

case_application_imports_infra_package() {
  new_repo application_imports_infra_package; with_fake_package pg
  printf 'import { Client } from "pg";\nexport const db = new Client();\n' > src/application/leak.ts
  expect application_imports_infra_package fail "core-no-infra-packages"
  record application_imports_infra_package
}

case_infrastructure_imports_infra_package_ok() {
  new_repo infrastructure_imports_infra_package_ok; with_fake_package pg
  printf 'import { Client } from "pg";\nexport const db = new Client();\n' > src/infrastructure/db.ts
  expect infrastructure_imports_infra_package_ok pass "VERIFY PASSED"
  record infrastructure_imports_infra_package_ok
}

case_domain_imports_io_builtin() {
  new_repo domain_imports_io_builtin
  printf 'import { createServer } from "node:http";\nexport const server = createServer();\n' > src/domain/leak.ts
  expect domain_imports_io_builtin fail "core-no-io-builtins"
  record domain_imports_io_builtin
}

# with_py_fake_package NAME: a local top-level package outside root_package "app", so
# import-linter treats it as external, and ruff and mypy can still resolve it.
with_py_fake_package() {
  mkdir -p "$1"
  printf 'class Session:\n    pass\n' > "$1/__init__.py"
}

case_py_domain_imports_infra_package() {
  new_py_repo py_domain_imports_infra_package; with_py_fake_package requests
  py_probe app/domain/leak.py requests Session
  expect py_domain_imports_infra_package fail "Domain and application do not import infrastructure packages BROKEN"
  record py_domain_imports_infra_package
}

case_py_application_imports_infra_package() {
  new_py_repo py_application_imports_infra_package; with_py_fake_package requests
  py_probe app/application/leak.py requests Session
  expect py_application_imports_infra_package fail "Domain and application do not import infrastructure packages BROKEN"
  record py_application_imports_infra_package
}

case_py_infrastructure_imports_infra_package_ok() {
  new_py_repo py_infrastructure_imports_infra_package_ok; with_py_fake_package requests
  py_probe app/infrastructure/http_client.py requests Session
  expect py_infrastructure_imports_infra_package_ok pass "Contracts: 6 kept, 0 broken"
  record py_infrastructure_imports_infra_package_ok
}

case_py_domain_imports_io_module() {
  new_py_repo py_domain_imports_io_module
  py_probe app/domain/leak.py socket socket
  expect py_domain_imports_io_module fail "Domain and application do not do I/O directly BROKEN"
  record py_domain_imports_io_module
}

case_py_domain_imports_cloud_subpackage() {
  new_py_repo py_domain_imports_cloud_subpackage
  mkdir -p google/cloud; : > google/__init__.py
  printf 'class Client:\n    pass\n' > google/cloud/__init__.py
  py_probe app/domain/leak.py google.cloud Client
  expect py_domain_imports_cloud_subpackage fail "imports google.cloud"
  record py_domain_imports_cloud_subpackage
}

case_py_application_imports_urllib_request() {
  new_py_repo py_application_imports_urllib_request
  py_probe app/application/leak.py urllib.request urlopen
  expect py_application_imports_urllib_request fail "imports urllib.request"
  record py_application_imports_urllib_request
}

case_py_domain_imports_os() {
  new_py_repo py_domain_imports_os
  py_probe app/domain/leak.py os sep
  expect py_domain_imports_os fail "imports os"
  record py_domain_imports_os
}

case_py_domain_calls_open() {
  new_py_repo py_domain_calls_open
  printf 'def load() -> str:\n    with open("orders.txt") as f:\n        return f.read()\n' > app/domain/leak.py
  expect py_domain_calls_open fail "calls open()"
  record py_domain_calls_open
}

case_py_domain_method_named_open_ok() {
  new_py_repo py_domain_method_named_open_ok
  printf 'class Account:\n    def open(self) -> None:\n        pass\n\n\ndef start(account: Account) -> None:\n    account.open()\n' > app/domain/account.py
  py_probe app/domain/parsing.py urllib.parse quote
  expect py_domain_method_named_open_ok pass "VERIFY PASSED"
  record py_domain_method_named_open_ok
}

case_py_infrastructure_imports_os_ok() {
  new_py_repo py_infrastructure_imports_os_ok
  py_probe app/infrastructure/settings.py os environ
  expect py_infrastructure_imports_os_ok pass "VERIFY PASSED"
  record py_infrastructure_imports_os_ok
}

case_domain_calls_global_fetch() {
  new_repo domain_calls_global_fetch
  printf 'export const load = () => fetch("https://example.invalid/orders");\n' > src/domain/leak.ts
  expect domain_calls_global_fetch fail "Unexpected use of 'fetch'"
  record domain_calls_global_fetch
}

case_application_reads_process_env() {
  new_repo application_reads_process_env
  printf 'export const region = process.env.REGION;\n' > src/application/leak.ts
  expect application_reads_process_env fail "Unexpected use of 'process'"
  record application_reads_process_env
}

case_domain_uses_globalthis_fetch() {
  new_repo domain_uses_globalthis_fetch
  printf 'export const load = () => globalThis.fetch("https://example.invalid/orders");\n' > src/domain/leak.ts
  expect domain_uses_globalthis_fetch fail "globalThis.fetch"
  record domain_uses_globalthis_fetch
}

case_infrastructure_calls_fetch_ok() {
  new_repo infrastructure_calls_fetch_ok
  printf 'export const load = () => fetch(process.env.ORDERS_URL ?? "https://example.invalid/orders");\n' > src/infrastructure/http.ts
  expect infrastructure_calls_fetch_ok pass "VERIFY PASSED"
  record infrastructure_calls_fetch_ok
}

# --- secrets and links profiles --------------------------------------------------------

# fake_token: a GitHub-token-shaped string made at run time, so no secret-shaped literal is
# ever committed to this repo (GitHub push protection would block it).
fake_token() { printf 'ghp_%s' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"; }

case_secrets_clean_pass() {
  new_repo secrets_clean_pass; set_env VERIFY_PROFILES "ts secrets"
  expect secrets_clean_pass pass "=== VERIFY PASSED (ts secrets) ==="; record secrets_clean_pass
}

case_secrets_catches_token() {
  new_repo secrets_catches_token; set_env VERIFY_PROFILES "ts secrets"
  printf 'export const token = "%s";\n' "$(fake_token)" > src/infrastructure/config.ts
  expect secrets_catches_token fail "SECRETS PROFILE FAILED"; record secrets_catches_token
}

case_secrets_catches_committed_token() {
  new_repo secrets_catches_committed_token; set_env VERIFY_PROFILES "ts secrets"
  printf 'export const token = "%s";\n' "$(fake_token)" > src/infrastructure/config.ts
  git add -A; commit "add config"
  expect secrets_catches_committed_token fail "SECRETS PROFILE FAILED"; record secrets_catches_committed_token
}

case_secrets_ignores_gitignored() {
  new_repo secrets_ignores_gitignored; set_env VERIFY_PROFILES "ts secrets"
  printf 'local.env\n' >> .gitignore; git add .gitignore; commit "ignore local.env"
  printf 'TOKEN=%s\n' "$(fake_token)" > local.env
  expect secrets_ignores_gitignored pass "=== VERIFY PASSED (ts secrets) ==="; record secrets_ignores_gitignored
}

case_secrets_missing_tool() {
  # Profile on its own: gitleaks may share a PATH folder with node.
  new_repo secrets_missing_tool; set_env VERIFY_PROFILES "secrets"
  expect secrets_missing_tool fail "gitleaks is not installed" PATH="$(path_without gitleaks)"
  record secrets_missing_tool
}

case_links_clean_pass() {
  new_repo links_clean_pass; set_env VERIFY_PROFILES "ts links"
  mkdir -p docs; printf '# Guide\n\n## Setup\n' > docs/guide.md
  printf '# Readme\n\nSee [setup](docs/guide.md#setup) and [the web](https://example.invalid/).\n' > README.md
  expect links_clean_pass pass "=== VERIFY PASSED (ts links) ==="; record links_clean_pass
}

case_links_missing_file() {
  new_repo links_missing_file; set_env VERIFY_PROFILES "ts links"
  printf '# Readme\n\nSee [the ADR](docs/adr/0002-missing.md).\n' > README.md
  expect links_missing_file fail "LINKS PROFILE FAILED"; record links_missing_file
}

case_links_missing_anchor() {
  new_repo links_missing_anchor; set_env VERIFY_PROFILES "ts links"
  mkdir -p docs; printf '# Guide\n' > docs/guide.md
  printf '# Readme\n\nSee [setup](docs/guide.md#setup).\n' > README.md
  expect links_missing_anchor fail "LINKS PROFILE FAILED"; record links_missing_anchor
}

case_links_missing_tool() {
  new_repo links_missing_tool; set_env VERIFY_PROFILES "links"
  expect links_missing_tool fail "lychee is not installed" PATH="$(path_without lychee)"
  record links_missing_tool
}

# --- agent-hooks module ----------------------------------------------------------------

# with_hooks: install modules/agent-hooks into the current scratch repo.
with_hooks() {
  cp -R "$ROOT/modules/agent-hooks/." .
  git add -A; commit "install agent-hooks"
}

# stop_hook NAME INPUT_JSON: run the Stop hook the way Claude Code or Codex would.
stop_hook() {
  set +e
  printf '%s' "$2" | env CI=false BASE_REF=main ./scripts/agent-stop-check.sh > "$WORK/out.log" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

case_stop_hook_clean_tree_silent() {
  new_repo stop_hook_clean_tree_silent; with_hooks
  stop_hook x '{"stop_hook_active": false}'
  if [ ! -s "$WORK/out.log" ]; then report stop_hook_clean_tree_silent 1 ""
  else report stop_hook_clean_tree_silent 0 "hook printed output with nothing changed"; fi
  record stop_hook_clean_tree_silent
}

case_stop_hook_passing_verify_silent() {
  new_repo stop_hook_passing_verify_silent; with_hooks
  printf 'export const label = "orders";\n' > src/domain/label.ts
  stop_hook x '{"stop_hook_active": false}'
  if [ ! -s "$WORK/out.log" ]; then report stop_hook_passing_verify_silent 1 ""
  else report stop_hook_passing_verify_silent 0 "hook blocked although verify passes"; fi
  record stop_hook_passing_verify_silent
}

case_stop_hook_blocks_failing_verify() {
  new_repo stop_hook_blocks_failing_verify; with_hooks
  printf 'export const bad: any = 1;\n' > src/domain/bad.ts
  stop_hook x '{"session_id": "s", "stop_hook_active": false}'
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("decision")=="block" and "verify" in d.get("reason","") else 1)' "$WORK/out.log" 2>/dev/null; then
    report stop_hook_blocks_failing_verify 1 ""
  else report stop_hook_blocks_failing_verify 0 "expected a block decision with verify's output"; fi
  record stop_hook_blocks_failing_verify
}

case_stop_hook_lets_second_stop_through() {
  new_repo stop_hook_lets_second_stop_through; with_hooks
  printf 'export const bad: any = 1;\n' > src/domain/bad.ts
  stop_hook x '{"session_id": "s", "stop_hook_active": true}'
  if [ ! -s "$WORK/out.log" ]; then report stop_hook_lets_second_stop_through 1 ""
  else report stop_hook_lets_second_stop_through 0 "hook blocked again after stop_hook_active (would loop)"; fi
  record stop_hook_lets_second_stop_through
}

case_pre_push_blocks_failing_verify() {
  new_repo pre_push_blocks_failing_verify; with_hooks
  git init -q --bare "$WORK/pre_push_remote.git"; git remote add origin "$WORK/pre_push_remote.git"
  git config core.hooksPath .githooks
  printf 'export const bad: any = 1;\n' > src/domain/bad.ts; git add -A; commit "bad"
  set +e; env CI=false BASE_REF=main git push -q origin work > "$WORK/out.log" 2>&1; local rc=$?; set -e
  if [ "$rc" -ne 0 ] && ! git ls-remote --exit-code origin work >/dev/null 2>&1; then
    report pre_push_blocks_failing_verify 1 ""
  else report pre_push_blocks_failing_verify 0 "push went through with verify failing"; fi
  record pre_push_blocks_failing_verify
}

case_pre_push_allows_passing_verify() {
  new_repo pre_push_allows_passing_verify; with_hooks
  git init -q --bare "$WORK/pre_push_ok.git"; git remote add origin "$WORK/pre_push_ok.git"
  git config core.hooksPath .githooks
  set +e; env CI=false BASE_REF=main git push -q origin work > "$WORK/out.log" 2>&1; local rc=$?; set -e
  if [ "$rc" -eq 0 ] && git ls-remote --exit-code origin work >/dev/null 2>&1; then
    report pre_push_allows_passing_verify 1 ""
  else report pre_push_allows_passing_verify 0 "push blocked although verify passes (exit $rc)"; fi
  record pre_push_allows_passing_verify
}

ALL_CASES="skills_frontmatter skills_linked workflows_lint_clean
  workflows_lint_catches_bad_expression workflows_lint_catches_injection empty_profiles unknown_profile missing_verify_env missing_package_script
  missing_tool_pnpm missing_tool_uv failing_lint_stops failing_test_stops
  missing_required_dir domain_imports_infrastructure domain_type_import_infrastructure
  skip_without_reason skip_with_reason suppression_without_reason suppression_with_reason
  python_skip_without_reason python_skip_with_reason_equals python_ignore_without_reason
  python_ignore_with_reason untracked_file_with_skip untracked_file_with_skip_reason
  deleted_test_committed deleted_test_uncommitted test_renamed_to_non_test
  test_moved_stays_test base_missing_in_ci base_missing_locally_warns ci_base_ref
  first_push_clean first_push_with_skip clean_pass
  py_clean_pass py_domain_imports_infrastructure py_application_imports_infrastructure
  py_presentation_imports_infrastructure py_domain_imports_application py_failing_ruff_stops
  py_type_error py_no_tests_fails py_no_tests_allowed_while_bootstrapping
  run_from_subdirectory run_from_outside_repo run_through_symlink
  domain_reaches_infrastructure_via_barrel domain_imports_infrastructure_via_alias
  domain_imports_infra_package application_imports_infra_package
  infrastructure_imports_infra_package_ok domain_imports_io_builtin
  py_domain_imports_infra_package py_application_imports_infra_package
  py_infrastructure_imports_infra_package_ok py_domain_imports_io_module
  py_domain_imports_cloud_subpackage py_application_imports_urllib_request py_domain_imports_os
  py_domain_calls_open py_domain_method_named_open_ok py_infrastructure_imports_os_ok
  domain_calls_global_fetch application_reads_process_env domain_uses_globalthis_fetch
  infrastructure_calls_fetch_ok
  secrets_clean_pass secrets_catches_token secrets_catches_committed_token secrets_ignores_gitignored
  secrets_missing_tool links_clean_pass links_missing_file links_missing_anchor links_missing_tool
  stop_hook_clean_tree_silent stop_hook_passing_verify_silent stop_hook_blocks_failing_verify
  stop_hook_lets_second_stop_through pre_push_blocks_failing_verify pre_push_allows_passing_verify"

ran=0
for name in $ALL_CASES; do
  want_case "$name" || continue
  ran=$((ran + 1))
  c "$name"
  if [ -f "$WORK/count.$name" ]; then
    read -r p f rest < "$WORK/count.$name"
    pass_count=$((pass_count + p)); fail_count=$((fail_count + f)); failures="$failures ${rest:-}"
  fi
done

[ "$ran" -gt 0 ] || { echo "no cases match '$FILTER'" >&2; exit 2; }
echo
echo "selftest: $pass_count passed, $fail_count failed"
if [ "$fail_count" -ne 0 ]; then
  echo "failed:$failures" >&2
  exit 1
fi
