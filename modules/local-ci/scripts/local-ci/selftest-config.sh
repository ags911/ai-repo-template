#!/usr/bin/env bash
# Native, credential-free checks of configuration rejection before a container starts.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/scripts/local-ci" "$WORK/bin"
cp "$HERE/run.sh" "$HERE/lane.sh" "$WORK/repo/scripts/local-ci/"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/docker"
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH" LOCAL_CI_BASE_REF=main
cd "$WORK/repo"
printf 'VERIFY_PROFILES="python"\n' > .verify.env
printf 'FROM alpine:3.22\n' > scripts/local-ci/Dockerfile
printf 'basic check - echo basic\n' > scripts/local-ci/lanes.conf
git init -q -b main
git add .
git -c commit.gpgsign=false -c user.name=selftest -c user.email=selftest@example.invalid commit -qm fixture
rc=0
bash scripts/local-ci/run.sh > "$WORK/output" 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -q 'plan omits configured profile: python' "$WORK/output"
printf 'python verify - bash scripts/profiles/python.sh\n' >> scripts/local-ci/lanes.conf
rc=0
bash scripts/local-ci/run.sh > "$WORK/output" 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -q 'plan omits configured profile: repository' "$WORK/output"
rc=0
bash scripts/local-ci/run.sh --jobs 0 > "$WORK/output" 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -q 'positive number' "$WORK/output"
echo 'local-ci configuration selftest: 3 passed, 0 failed'
