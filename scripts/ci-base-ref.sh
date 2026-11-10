#!/usr/bin/env bash
# Prints the ref that check-suppressions.sh should diff against in CI.
#   pull_request        -> origin/<base branch>
#   push                -> the commit before the push (covers every pushed commit)
#   first push (no prior commit) -> the empty tree, so the whole initial content is checked
# Inputs (env): EVENT, PR_BASE, BEFORE. See .github/workflows/verify.yml.
set -euo pipefail
zero=0000000000000000000000000000000000000000
case "${EVENT:-}" in
  pull_request) echo "origin/${PR_BASE:?PR_BASE is required for pull_request}" ;;
  push)
    if [ -z "${BEFORE:-}" ] || [ "$BEFORE" = "$zero" ]; then
      git hash-object -t tree /dev/null
    else
      echo "$BEFORE"
    fi ;;
  *) echo "ci-base-ref: unsupported event '${EVENT:-}'" >&2; exit 1 ;;
esac
