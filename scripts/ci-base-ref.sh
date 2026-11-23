#!/usr/bin/env bash
# Prints the ref that check-suppressions.sh should diff against in CI.
#   pull_request        -> origin/<base branch>
#   push                -> the commit before the push (covers every pushed commit)
#   first push (no prior commit) -> the empty tree, so the whole initial content is checked
#   workflow_dispatch, schedule -> a run with no diff of its own:
#       on a branch      -> the merge base with origin/<default branch>
#       on the default branch itself -> HEAD's first parent (HEAD^1; for a merge commit
#         that is the branch it merged into), or the empty tree for a root commit
# Inputs (env): EVENT, PR_BASE, BEFORE, DEFAULT_BRANCH (optional: otherwise origin/HEAD,
# then main, then master). See .github/workflows/verify.yml.
set -euo pipefail
zero=0000000000000000000000000000000000000000

# default_branch: the name of the repository's default branch, as a remote-tracking ref.
default_branch() {
  local b
  if [ -n "${DEFAULT_BRANCH:-}" ]; then echo "$DEFAULT_BRANCH"; return; fi
  if b=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then echo "${b#origin/}"; return; fi
  for b in main master; do
    if git rev-parse --verify -q "refs/remotes/origin/$b^{commit}" >/dev/null; then echo "$b"; return; fi
  done
  echo "ci-base-ref: cannot find the default branch; set DEFAULT_BRANCH" >&2
  return 1
}

# manual_base: the base for an event that carries none of its own (workflow_dispatch, schedule).
manual_base() {
  local b ref
  b=$(default_branch)
  ref="refs/remotes/origin/$b"
  git rev-parse --verify -q "$ref^{commit}" >/dev/null \
    || { echo "ci-base-ref: origin/$b not found (fetch with full history)" >&2; return 1; }
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$ref^{commit}")" ]; then
    # On the default branch itself: the first parent (the empty tree for a root commit).
    if git rev-parse --verify -q HEAD^1 >/dev/null; then git rev-parse HEAD^1
    else git hash-object -t tree /dev/null
    fi
  else
    git merge-base "$ref" HEAD \
      || { echo "ci-base-ref: no merge base between origin/$b and HEAD" >&2; return 1; }
  fi
}

case "${EVENT:-}" in
  pull_request) echo "origin/${PR_BASE:?PR_BASE is required for pull_request}" ;;
  push)
    if [ -z "${BEFORE:-}" ] || [ "$BEFORE" = "$zero" ]; then
      git hash-object -t tree /dev/null
    else
      echo "$BEFORE"
    fi ;;
  workflow_dispatch|schedule) manual_base ;;
  *) echo "ci-base-ref: unsupported event '${EVENT:-}'" >&2; exit 1 ;;
esac
