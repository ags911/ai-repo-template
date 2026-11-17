#!/usr/bin/env bash
# Resumable local CI: runs this repo's checks in Docker on your machine, outside GitHub
# Actions, and can post the result as a commit status. Lanes and steps come from lanes.conf;
# the image from the Dockerfile beside it. See modules/README.md, section "local-ci".
#
# Usage: scripts/local-ci/run.sh [--post] [--fresh] [--lane NAME]... [--config DIR]
#   --post        post the result to GitHub as a commit status (needs gh, signed in, and the
#                 commit pushed). Without it, nothing is posted.
#   --fresh       forget this commit's passed steps and the lanes' clones; run everything.
#   --lane NAME   run only this lane (repeatable). Default: every lane in lanes.conf.
#   --config DIR  folder holding lanes.conf and Dockerfile. Default: this script's folder.
#
# It tests the commit at HEAD, not uncommitted changes. Exit codes: 0 every lane passed (and
# the status was posted, with --post); 1 a lane failed; 2 a usage or setup error, or GitHub
# refused the status.
#
# Settings (environment variables):
#   LOCAL_CI_GAP=60          a step that fails after the clock jumped this many seconds
#                            (sleep, `docker pause`) reruns once
#   LOCAL_CI_TICK=5          how often, in seconds, each lane checks the clock
#   LOCAL_CI_NET_TRIES=3     attempts for steps flagged "net", and for building the image
#   LOCAL_CI_NET_BACKOFF=10  seconds before the 2nd attempt; it grows with each attempt
#   LOCAL_CI_CONTEXT=local-ci  the commit status's name (what branch protection requires)
#   LOCAL_CI_POST_BACKOFF=5  first wait between status attempts; doubles, up to 60
#   LOCAL_CI_NAME            prefix for containers, volumes and images. Default: from the
#                            repo folder's name and path.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR=$HERE
POST=0
FRESH=0
WANT_LANES=""

die() { echo "local-ci: $*" >&2; exit 2; }
say() { echo "local-ci: $*"; }

while [ $# -gt 0 ]; do
  case $1 in
    --post) POST=1 ;;
    --fresh) FRESH=1 ;;
    --lane) [ $# -ge 2 ] || die "--lane needs a name"; WANT_LANES="$WANT_LANES $2"; shift ;;
    --config) [ $# -ge 2 ] || die "--config needs a folder"; CONFIG_DIR=$(cd "$2" && pwd); shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

GAP=${LOCAL_CI_GAP:-60}
TICK=${LOCAL_CI_TICK:-5}
NET_TRIES=${LOCAL_CI_NET_TRIES:-3}
NET_BACKOFF=${LOCAL_CI_NET_BACKOFF:-10}
CONTEXT=${LOCAL_CI_CONTEXT:-local-ci}
POST_BACKOFF=${LOCAL_CI_POST_BACKOFF:-5}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it inside a git repository"
cd "$ROOT"
SHA=$(git rev-parse --verify HEAD 2>/dev/null) || die "no commit to test yet"
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd)
STATE=$(cd "$(git rev-parse --git-dir)" && pwd)/local-ci/$SHA
CONF=$CONFIG_DIR/lanes.conf
[ -f "$CONF" ] || die "no lanes.conf in $CONFIG_DIR"
[ -f "$CONFIG_DIR/Dockerfile" ] || die "no Dockerfile in $CONFIG_DIR"
command -v docker >/dev/null || die "docker is not installed"
docker info >/dev/null 2>&1 || die "docker is not running"
if [ "$POST" = 1 ]; then command -v gh >/dev/null || die "--post needs the gh CLI"; fi

# One name per checkout, so two clones of a repo don't share containers or volumes.
if [ -n "${LOCAL_CI_NAME:-}" ]; then
  NAME=$LOCAL_CI_NAME
else
  base=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9\n' '-' | sed 's/^-*//; s/-*$//')
  NAME=local-ci-${base:-repo}-$(printf '%s' "$ROOT" | git hash-object --stdin | cut -c1-6)
fi
case $NAME in *[!a-z0-9-]*|-*|"") die "LOCAL_CI_NAME must be lowercase letters, digits and -" ;; esac

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  say "note: uncommitted changes are not tested; this run tests HEAD"
fi

# --- read lanes.conf ---------------------------------------------------------
# One step per line: lane, step, flags, then the command (the rest of the line).
TMP=$(mktemp -d "${TMPDIR:-/tmp}/local-ci.XXXXXX")
FOLLOWERS=""
cleanup() {
  # shellcheck disable=SC2086 # reason: FOLLOWERS is a list of process ids
  [ -z "$FOLLOWERS" ] || kill $FOLLOWERS 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo; say "stopped; the lane containers keep running. Run again to follow them."; exit 130' INT TERM

ALL_LANES=""
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line=${line%$'\r'}
  trimmed=${line#"${line%%[![:space:]]*}"}
  case $trimmed in ''|'#'*) continue ;; esac
  read -r lane step flags cmd <<< "$trimmed"
  for v in "$lane" "$step"; do
    case $v in ''|*[!A-Za-z0-9_-]*) die "lanes.conf line $n: names may use letters, digits, - and _: $v" ;; esac
  done
  case $flags in -|net) ;; *) die "lanes.conf line $n: flags must be - or net, not '$flags'" ;; esac
  [ -n "$cmd" ] || die "lanes.conf line $n: no command"
  if [ -f "$TMP/$lane.steps" ] && cut -f1 "$TMP/$lane.steps" | grep -qx "$step"; then
    die "lanes.conf line $n: step $step appears twice in lane $lane"
  fi
  case " $ALL_LANES " in *" $lane "*) ;; *) ALL_LANES="$ALL_LANES $lane" ;; esac
  printf '%s\t%s\t%s\n' "$step" "$flags" "$cmd" >> "$TMP/$lane.steps"
done < "$CONF"
[ -n "$ALL_LANES" ] || die "lanes.conf has no steps"

LANES=""
for l in ${WANT_LANES:-$ALL_LANES}; do
  case " $ALL_LANES " in *" $l "*) LANES="$LANES $l" ;; *) die "no lane '$l' in lanes.conf" ;; esac
done

# --- the image ---------------------------------------------------------------
# Tagged with a hash of its inputs (the Dockerfile and anything in image/), so editing them
# builds a new image; older tags are then pruned.
ctx=$CONFIG_DIR/image
[ -d "$ctx" ] || { ctx=$TMP/empty-context; mkdir -p "$ctx"; }
tag=$( { git hash-object "$CONFIG_DIR/Dockerfile"
         if [ -d "$CONFIG_DIR/image" ]; then
           (cd "$CONFIG_DIR/image" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
              printf '%s %s\n' "$(git hash-object "$f")" "$f"; done)
         fi; } | git hash-object --stdin | cut -c1-12)
IMAGE=$NAME:$tag
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  say "building image $IMAGE"
  try=1
  until docker build -t "$IMAGE" -f "$CONFIG_DIR/Dockerfile" "$ctx"; do
    [ "$try" -lt "$NET_TRIES" ] || die "image build failed $try times"
    say "image build failed; retry $((try + 1))/$NET_TRIES in $((NET_BACKOFF * try))s"
    sleep $((NET_BACKOFF * try))
    try=$((try + 1))
  done
fi
docker image ls "$NAME" --format '{{.Tag}}' | while IFS= read -r t; do
  [ "$t" = "$tag" ] || docker image rm "$NAME:$t" >/dev/null 2>&1 || true
done
# Checkpoints of commits not touched for two weeks.
find "$(dirname "$STATE")" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null || true

# --- start or rejoin each lane -----------------------------------------------
lane_status() { docker inspect -f '{{.State.Status}} {{index .Config.Labels "local-ci.sha"}}' "$NAME-$1" 2>/dev/null || true; }

# follow LANE TAIL: stream the lane's log with a [lane] prefix, in the background.
follow() {
  docker logs -f --tail "$2" "$NAME-$1" 2>&1 | while IFS= read -r l; do printf '[%s] %s\n' "$1" "$l"; done &
  FOLLOWERS="$FOLLOWERS $!"
}

PENDING=""
RESULTS=""
for lane in $LANES; do
  st=$(lane_status "$lane")
  case $st in
    running*|paused*|restarting*)
      [ "${st#* }" = "$SHA" ] || die "lane $lane is running for commit ${st#* }; wait for it, or stop it: docker rm -f $NAME-$lane"
      [ "$FRESH" = 0 ] || die "lane $lane is still running; --fresh needs it stopped: docker rm -f $NAME-$lane"
      say "lane $lane is already running for this commit; following it"
      follow "$lane" 30
      PENDING="$PENDING $lane"
      continue ;;
    ?*) docker rm -f "$NAME-$lane" >/dev/null ;;
  esac
  sd=$STATE/$lane
  if [ "$FRESH" = 1 ]; then
    rm -rf "$sd"
    docker volume rm "$NAME-$lane" >/dev/null 2>&1 || true
  fi
  mkdir -p "$sd"
  # A marker is named after the step and a hash of its command, flags and image, so editing a
  # step or the image reruns it.
  all_done=1
  : > "$sd/steps"
  while IFS=$'\t' read -r step flags cmd; do
    marker=$step.$(printf '%s\t%s\t%s' "$IMAGE" "$flags" "$cmd" | git hash-object --stdin | cut -c1-10).ok
    printf '%s\t%s\t%s\t%s\n' "$step" "$flags" "$marker" "$cmd" >> "$sd/steps"
    [ -f "$sd/$marker" ] || all_done=0
  done < "$TMP/$lane.steps"
  if [ "$all_done" = 1 ]; then
    say "lane $lane: every step passed earlier at this commit"
    RESULTS="$RESULTS $lane=pass"
    continue
  fi
  docker run -d --init --name "$NAME-$lane" \
    --label "local-ci.sha=$SHA" --label "local-ci.name=$NAME" \
    -v "$NAME-$lane:/work" -v "$GIT_COMMON:/src.git:ro" -v "$sd:/state" \
    -v "$HERE/lane.sh:/ci/lane.sh:ro" \
    -e "LANE=$lane" -e "SHA=$SHA" -e "IMAGE=$IMAGE" -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
    -e "LOCAL_CI_GAP=$GAP" -e "LOCAL_CI_TICK=$TICK" \
    -e "LOCAL_CI_NET_TRIES=$NET_TRIES" -e "LOCAL_CI_NET_BACKOFF=$NET_BACKOFF" \
    "$IMAGE" bash /ci/lane.sh >/dev/null
  say "lane $lane started in container $NAME-$lane"
  follow "$lane" all
  PENDING="$PENDING $lane"
done

# --- wait --------------------------------------------------------------------
# Poll rather than `docker wait`: after the laptop sleeps, the Docker connection can drop. The
# containers carry on regardless; give up only if Docker stays unreachable for 5 minutes.
misses=0
while [ -n "${PENDING// /}" ]; do
  still=""
  for lane in $PENDING; do
    if ! st=$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$NAME-$lane" 2>/dev/null); then
      misses=$((misses + 1))
      [ "$misses" -lt 100 ] || die "Docker unreachable for 5 minutes; the lanes may still be running. Run again to follow them."
      still="$still $lane"
      continue
    fi
    misses=0
    case $st in
      exited*|dead*)
        code=${st#* }
        sleep 1  # let the log stream print its last lines
        docker rm -f "$NAME-$lane" >/dev/null 2>&1 || true
        if [ "$code" = 0 ]; then RESULTS="$RESULTS $lane=pass"
        elif [ -f "$STATE/$lane/failed" ]; then RESULTS="$RESULTS $lane=fail:$(cat "$STATE/$lane/failed")"
        else RESULTS="$RESULTS $lane=stopped:$code"
        fi ;;
      *) still="$still $lane" ;;
    esac
  done
  PENDING=$still
  [ -z "${PENDING// /}" ] || sleep 3
done

# --- report ------------------------------------------------------------------
ok=1
desc=""
echo
for r in $RESULTS; do
  lane=${r%%=*}
  res=${r#*=}
  case $res in
    pass) say "PASS $lane" ;;
    fail:*) ok=0; say "FAIL $lane at step ${res#fail:}"; desc="$desc, $lane failed at ${res#fail:}" ;;
    stopped:*) ok=0; say "FAIL $lane: container stopped with exit ${res#stopped:}"; desc="$desc, $lane stopped" ;;
  esac
done
if [ "$ok" = 1 ]; then state=success; desc="passed:$LANES"
else state=failure; desc=${desc#, }
fi

# post_status STATE DESCRIPTION: retry until GitHub takes it. A 4xx answer (other than 429)
# won't change on retry, so that stops.
post_status() {
  local delay=$POST_BACKOFF attempt=1 out
  while :; do
    if out=$(gh api -X POST "repos/{owner}/{repo}/statuses/$SHA" -f "state=$1" \
               -f "context=$CONTEXT" -f "description=${2:0:140}" 2>&1 >/dev/null); then
      say "posted status $CONTEXT=$1 for $SHA"
      return 0
    fi
    case $out in
      *"HTTP 429"*) ;;
      *"HTTP 4"[0-9][0-9]*) echo "local-ci: GitHub refused the status: $out" >&2; return 1 ;;
    esac
    say "posting the status failed (attempt $attempt): $(printf '%s' "$out" | head -n 1); retrying in ${delay}s"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    [ "$delay" -le 60 ] || delay=60
  done
}
if [ "$POST" = 1 ]; then post_status "$state" "$desc" || exit 2; fi
[ "$ok" = 1 ]
