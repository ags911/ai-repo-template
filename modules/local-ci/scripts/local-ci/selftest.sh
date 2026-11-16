#!/usr/bin/env bash
# Self-test for the local-ci module. Builds a throwaway repo (under a path with spaces) with a
# small Alpine image and test lanes, and checks, against real containers:
#   - a rerun skips passed steps, and a lane whose steps all passed starts no container
#   - a failing step fails its lane and names the step
#   - a step flagged net is retried; the same step without the flag is not
#   - sleep: a step that fails after `docker pause` reruns once and passes; without the pause
#     it fails
#   - kill and resume: the lane keeps running when run.sh dies; a rerun follows it; after the
#     container is killed mid-step, a rerun skips the passed steps and runs the rest
#   - a new clone clears the lane's markers
#   - editing the Dockerfile builds a new image tag and prunes the old one
#   - nothing is posted without --post; with it, the status is retried until it gets
#     through, and a 4xx answer stops it (a fake gh, so nothing reaches GitHub)
# It tests the run.sh and lane.sh beside it, with its own lanes.conf, not yours.
#
# Usage: scripts/local-ci/selftest.sh     Needs bash, git and a running Docker; pulls
# alpine on the first run. Takes about two minutes.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  echo "selftest needs a running Docker" >&2; exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-ci-selftest.XXXXXX")
REPO="$WORK/repo with spaces"
NAME=local-ci-selftest-$$
export LOCAL_CI_BASE_REF=main
export LOCAL_CI_NAME=$NAME LOCAL_CI_GAP=4 LOCAL_CI_TICK=1 LOCAL_CI_NET_BACKOFF=1 LOCAL_CI_POST_BACKOFF=1

cleanup() {
  docker ps -aq --filter "label=local-ci.name=$NAME" | while read -r c; do docker rm -f "$c" >/dev/null 2>&1; done
  docker volume ls -q --filter "name=$NAME-" | while read -r v; do docker volume rm "$v" >/dev/null 2>&1; done
  docker image ls "$NAME" --format '{{.Repository}}:{{.Tag}}' | while read -r i; do docker image rm -f "$i" >/dev/null 2>&1; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- the throwaway repo --------------------------------------------------------
mkdir -p "$REPO/scripts/local-ci" "$REPO/steps" "$WORK/bin"
cp "$HERE/run.sh" "$HERE/lane.sh" "$REPO/scripts/local-ci/"
cat > "$REPO/scripts/local-ci/Dockerfile" <<'EOF'
FROM alpine:3.22
RUN apk add --no-cache bash git
EOF
cat > "$REPO/scripts/local-ci/lanes.conf" <<'EOF'
# selftest lanes
basic  one     -    echo one
basic  two     -    echo two
basic  three   -    echo three
fail   bad     -    echo about to fail; exit 3
net    fetch   net  sh steps/flaky-once.sh net 0
nonet  fetch   -    sh steps/flaky-once.sh nonet 0
pause  sleepy  -    sh steps/flaky-once.sh pause 8
slow   one     -    echo one
slow   two     -    echo two
slow   wait    -    sleep 8
slow   four    -    echo four
bound1 wait    -    sleep 2
bound2 wait    -    sleep 2
bound3 wait    -    sleep 2
EOF
# Fails the first time it runs in a container, after sleeping $2 seconds; passes after that.
cat > "$REPO/steps/flaky-once.sh" <<'EOF'
f=/tmp/attempted-$1
if [ -f "$f" ]; then echo "second attempt passes"; exit 0; fi
touch "$f"; sleep "$2"; echo "first attempt fails"; exit 1
EOF
# A fake gh: logs each call; fails the first $GH_FAIL_FIRST calls like a dropped network;
# answers 404 when GH_REFUSE is set.
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ "$(wc -l < "$GH_LOG")" -le "${GH_FAIL_FIRST:-0}" ]; then echo "error connecting to api.github.com" >&2; exit 1; fi
if [ -n "${GH_REFUSE:-}" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
echo '{}'
EOF
chmod +x "$WORK/bin/gh"
git -C "$REPO" init -q -b main
git -C "$REPO" add -A
git -C "$REPO" -c user.name=selftest -c user.email=selftest@example.invalid commit -qm base
STATE="$REPO/.git/local-ci/$(git -C "$REPO" rev-parse HEAD)"

# --- helpers -------------------------------------------------------------------
passed=0
failed=0
failures=""
# ci OUT [run.sh args...]: run it in the repo, output to $WORK/OUT; returns its exit code.
ci() { local out=$1; shift; (cd "$REPO" && ./scripts/local-ci/run.sh "$@") > "$WORK/$out" 2>&1; }
# expect CASE OUT GOT WANT [PATTERN | !PATTERN]...: the exit code, and what the output must or
# must not contain (fixed strings).
expect() {
  local name=$1 out=$WORK/$2 got=$3 want=$4 p why=""
  shift 4
  [ "$got" = "$want" ] || why="exit $got, wanted $want"
  for p in "$@"; do
    case $p in
      !*) if grep -qF -- "${p#!}" "$out"; then why="${why:+$why; }has '${p#!}'"; fi ;;
      *) grep -qF -- "$p" "$out" || why="${why:+$why; }no '$p'" ;;
    esac
  done
  if [ -z "$why" ]; then
    echo "ok   $name"; passed=$((passed + 1))
  else
    echo "FAIL $name: $why"; sed 's/^/     | /' "$out"; failed=$((failed + 1)); failures="$failures $name"
  fi
}
check() {  # check CASE COMMAND...: passes when the command succeeds
  local name=$1; shift
  if "$@"; then echo "ok   $name"; passed=$((passed + 1))
  else echo "FAIL $name"; failed=$((failed + 1)); failures="$failures $name"; fi
}
# wait_for SECONDS COMMAND...: poll until the command succeeds; fail the selftest on timeout.
wait_for() {
  local limit=$(( $1 * 4 )); shift
  until "$@"; do
    limit=$((limit - 1))
    [ "$limit" -gt 0 ] || { echo "timed out waiting for: $*" >&2; exit 1; }
    sleep 0.25
  done
}
has() { grep -qF -- "$2" "$WORK/$1" 2>/dev/null; }
marker() { compgen -G "$STATE/$1/$2.*.ok" >/dev/null; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$NAME-$1" 2>/dev/null)" = true ]; }
tags() { docker image ls "$NAME" --format '{{.Tag}}'; }

# --- cases ---------------------------------------------------------------------
rc=0; ci invalid --jobs 0 || rc=$?
expect "zero concurrency is rejected" invalid "$rc" 2 "positive number"

rc=0; ci basic1 --lane basic || rc=$?
expect "first run passes" basic1 "$rc" 0 "building image" "pass one" "pass three" "PASS basic"
rc=0; ci basic2 --lane basic || rc=$?
expect "rerun skips a lane whose steps all passed" basic2 "$rc" 0 \
  "every step passed earlier" "!started in container" "!building image"

rc=0; ci fail --lane fail || rc=$?
expect "a failing step fails the lane and is named" fail "$rc" 1 "about to fail" "FAIL fail at step bad"

rc=0; ci net --lane net || rc=$?
expect "a net step is retried" net "$rc" 0 "retry 2/3" "second attempt passes" "PASS net"
rc=0; ci nonet --lane nonet || rc=$?
expect "a step without net is not retried" nonet "$rc" 1 "!retry" "FAIL nonet at step fetch"

# The scheduler must serialize when bounded to one and overlap when bounded to two.
start=$SECONDS
rc=0; ci serial --lane bound1 --lane bound2 --lane bound3 --jobs 1 || rc=$?
expect "bounded serial run passes" serial "$rc" 0 "PASS bound1" "PASS bound3"
serial=$((SECONDS - start))
start=$SECONDS
(ci parallel --lane bound1 --lane bound2 --lane bound3 --jobs 2 --fresh) & bound_pid=$!
max_active=0
while kill -0 "$bound_pid" 2>/dev/null; do
  count=$(docker ps -q --filter "label=local-ci.name=$NAME" | wc -l | tr -d ' ')
  [ "$count" -le "$max_active" ] || max_active=$count
  sleep 0.25
done
rc=0; wait "$bound_pid" || rc=$?
check "the scheduler starts two containers and never exceeds two" test "$max_active" = 2
expect "bounded parallel run passes" parallel "$rc" 0 "PASS bound1" "PASS bound3"
parallel=$((SECONDS - start))
check "parallel lanes finish faster than the serial control" test "$parallel" -lt "$serial"

# Sleep: pause the container while the step runs; it fails, sees the gap, reruns once.
(ci pause --lane pause) & pid=$!
wait_for 120 has pause "run  sleepy"
docker pause "$NAME-pause" >/dev/null
sleep $((LOCAL_CI_GAP + 3))
docker unpause "$NAME-pause" >/dev/null
rc=0; wait "$pid" || rc=$?
expect "a step failing after docker pause reruns once and passes" pause "$rc" 0 \
  "after a gap of over ${LOCAL_CI_GAP}s" "second attempt passes" "PASS pause"
rc=0; ci pause-control --lane pause --fresh || rc=$?
expect "the same step without a pause fails (control)" pause-control "$rc" 1 \
  "!after a gap" "FAIL pause at step sleepy"

# Kill and resume, part 1: run.sh dies; the lane carries on and a rerun follows it.
(ci slow1 --lane slow) & pid=$!
wait_for 120 has slow1 "run  wait"
kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
check "the lane keeps running after run.sh is killed" running slow
rc=0; ci slow2 --lane slow || rc=$?
expect "a rerun follows the running lane to the end" slow2 "$rc" 0 "already running for this commit" "PASS slow"

# Part 2: the container is killed mid-step; a rerun skips what passed and runs the rest.
(ci slow3 --lane slow --fresh) & pid=$!
wait_for 120 has slow3 "run  wait"
check "steps before the kill left markers" marker slow two
docker kill "$NAME-slow" >/dev/null
rc=0; wait "$pid" || rc=$?
expect "killing the container fails the run" slow3 "$rc" 1 "container stopped"
rc=0; ci slow4 --lane slow || rc=$?
expect "after a kill, a rerun skips passed steps and runs the rest" slow4 "$rc" 0 \
  "skip one" "skip two" "run  wait" "pass four" "!run  one" "!clone"

# A new clone (the volume is gone) clears the lane's markers, so every step runs.
rm -f "$STATE"/slow/four.*.ok
docker volume rm "$NAME-slow" >/dev/null
rc=0; ci slow5 --lane slow || rc=$?
expect "a new clone clears the lane's markers" slow5 "$rc" 0 "clone" "run  one" "run  four" "!skip one"

docker volume rm "$NAME-basic" >/dev/null
rc=0; ci deleted-volume --lane basic || rc=$?
expect "a fully passed lane reruns after its volume is deleted" deleted-volume "$rc" 0 "run  one" "!every step passed earlier"

# Editing the Dockerfile: a new tag, the old one pruned, and the steps rerun on the new image.
before=$(tags)
echo 'LABEL selftest=changed' >> "$REPO/scripts/local-ci/Dockerfile"
rc=0; ci image --lane basic || rc=$?
after=$(tags)
expect "editing the Dockerfile builds a new image and reruns the steps" image "$rc" 0 "building image" "run  one"
check "the old image tag is pruned" test "$(printf '%s\n' "$after" | wc -l | tr -d ' ')" = 1 -a "$after" != "$before"

# A changed prerequisite invalidates downstream checkpoints, even at the same SHA.
printf '\nbasic four - echo changed\n' >> "$REPO/scripts/local-ci/lanes.conf"
rc=0; ci prerequisite --lane basic || rc=$?
expect "a new downstream step runs" prerequisite "$rc" 0 "pass four"
sed -i.bak 's/basic  one     -    echo one/basic  one     -    echo changed-one/' "$REPO/scripts/local-ci/lanes.conf"
rc=0; ci invalidated --lane basic || rc=$?
expect "changed prerequisite invalidates later steps" invalidated "$rc" 0 "run  two" "run  four"

# Posting, with the fake gh first on PATH.
export PATH="$WORK/bin:$PATH" GH_LOG="$WORK/gh.log"
rc=0; ci nopost --lane basic || rc=$?
check "without --post nothing is posted" test "$rc" = 0 -a ! -e "$GH_LOG"
rc=0; GH_FAIL_FIRST=2 ci post --post --lane basic || rc=$?
expect "the status is retried until it gets through" post "$rc" 0 "attempt 2" "posted status local-ci-partial=success"
check "partial selection cannot publish the full context" grep -q 'context=local-ci-partial' "$GH_LOG"
check "it took three calls, the last with state=success for the commit" \
  grep -q "statuses/$(git -C "$REPO" rev-parse HEAD) .*state=success" <(sed -n 3p "$GH_LOG")
rm -f "$GH_LOG"
rc=0; ci postfail --post --lane fail || rc=$?
check "a failed lane posts state=failure naming the step" \
  test "$rc" = 1 -a "$(grep -c 'state=failure.*fail failed at bad' "$GH_LOG")" = 1
rm -f "$GH_LOG"
rc=0; GH_REFUSE=1 ci refused --post --lane basic || rc=$?
expect "a 4xx answer stops the retries" refused "$rc" 2 "GitHub refused the status" "!attempt"

echo
echo "local-ci selftest: $passed passed, $failed failed"
[ "$failed" = 0 ] || { echo "failed:$failures" >&2; exit 1; }
