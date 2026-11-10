#!/usr/bin/env bash
# Python profile: ruff (lint + format), mypy, pytest, and import-linter if configured.
# Uses `uv run --locked` when a uv.lock is present (fails if the lockfile is out of date
# instead of rewriting it), otherwise the active Python environment.
set -euo pipefail
source .verify.env
cd "${PY_DIR:-.}"

fail() { echo "PYTHON PROFILE FAILED: $*" >&2; exit 1; }
[ -f pyproject.toml ] || fail "no pyproject.toml in '$PWD'"

if [ -f uv.lock ]; then
  command -v uv >/dev/null || fail "uv.lock present but uv is not installed"
  run() { uv run --locked "$@"; }
else
  run() { python -m "$@"; }
fi

echo "--- ruff check";          run ruff check .
echo "--- ruff format --check"; run ruff format --check .
echo "--- mypy";                run mypy .

echo "--- pytest"
set +e; run pytest; rc=$?; set -e
if [ "$rc" -eq 5 ]; then
  [ "${ALLOW_EMPTY_TESTS:-0}" = "1" ] || fail "pytest collected no tests (set ALLOW_EMPTY_TESTS=1 only while bootstrapping)"
  echo "WARNING: no tests collected (ALLOW_EMPTY_TESTS=1)"
elif [ "$rc" -ne 0 ]; then
  fail "pytest exited $rc"
fi

if [ -f .importlinter ] || grep -q '^\[tool\.importlinter\]' pyproject.toml; then
  echo "--- lint-imports"
  if [ -f uv.lock ]; then uv run --locked lint-imports; else lint-imports; fi
fi
