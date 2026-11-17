#!/usr/bin/env bash
# Runs one lane's steps inside that lane's container. run.sh starts it; don't run it by hand.
#
# Mounts:  /src.git  the host repo's git directory, read-only (the clone source)
#          /work     this lane's Docker volume: the clone, kept between runs
#          /state    the host folder for this commit and lane: the step list and pass markers
# Env:     LANE, SHA, IMAGE, HOST_UID, HOST_GID, and the LOCAL_CI_* settings run.sh passes on.
#
# Each step that passes leaves a marker in /state, so a rerun skips it. A new clone clears the
# markers, because whatever earlier steps left in the old clone (installed dependencies,
# build output) is gone.
set -uo pipefail

: "${LANE:?}" "${SHA:?}" "${IMAGE:?}"
GAP=${LOCAL_CI_GAP:-60}
TICK=${LOCAL_CI_TICK:-5}
NET_TRIES=${LOCAL_CI_NET_TRIES:-3}
NET_BACKOFF=${LOCAL_CI_NET_BACKOFF:-10}

say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Files this container writes to /state belong to root; hand them to the host user so the
# host can delete them (it matters on Linux, where bind mounts keep owners as they are).
own() { [ -n "${HOST_UID:-}" ] && chown "$HOST_UID:${HOST_GID:-$HOST_UID}" "$@" 2>/dev/null; true; }

# --- the clone ---------------------------------------------------------------
key="$SHA $IMAGE"
if [ "$(cat /work/.key 2>/dev/null)" != "$key" ] || [ ! -d /work/repo/.git ]; then
  say "clone $SHA (a new clone clears this lane's markers)"
  rm -f /state/*.ok /state/failed
  rm -rf /work/repo /work/.key
  git -c safe.directory='*' clone -q --no-checkout --no-hardlinks /src.git /work/repo || exit 1
  git -C /work/repo -c advice.detachedHead=false checkout -q --detach "$SHA" || exit 1
  printf '%s\n' "$key" > /work/.key
fi

# --- sleep detection ---------------------------------------------------------
# watch_gap GAPFILE TICKFILE: every TICK seconds, record the time in TICKFILE. If the clock
# jumped by more than GAP since the last tick, the container was frozen (the laptop slept, or
# `docker pause`): write the jump to GAPFILE.
watch_gap() {
  local last now
  last=$(date +%s)
  while sleep "$TICK"; do
    now=$(date +%s)
    if [ $((now - last)) -gt "$GAP" ]; then echo "$((now - last))" > "$1"; fi
    echo "$now" > "$2"
    last=$now
  done
}

# run_once COMMAND: run it in the clone; set SLEPT=1 if a gap happened while it ran. A step
# that fails right after waking, before the watcher's next tick, is caught by comparing the
# clock with the last tick.
run_once() {
  local gapfile=/tmp/local-ci-gap tickfile=/tmp/local-ci-tick rc hb
  rm -f "$gapfile"
  date +%s > "$tickfile"
  watch_gap "$gapfile" "$tickfile" &
  hb=$!
  (cd /work/repo && bash -o pipefail -c "$1" < /dev/null)
  rc=$?
  kill "$hb" 2>/dev/null
  wait "$hb" 2>/dev/null
  SLEPT=0
  if [ -f "$gapfile" ] || [ $(( $(date +%s) - $(cat "$tickfile") )) -gt "$GAP" ]; then SLEPT=1; fi
  return "$rc"
}

# --- the steps ---------------------------------------------------------------
# /state/steps: one step per line, tab-separated: name, flags, marker file, command.
failed=""
while IFS=$'\t' read -r -u 3 step flags marker cmd; do
  if [ -f "/state/$marker" ]; then
    say "skip $step (passed earlier at this commit)"
    continue
  fi
  tries=1
  reran=0
  while :; do
    say "run  $step: $cmd"
    start=$(date +%s)
    run_once "$cmd"
    rc=$?
    took=$(( $(date +%s) - start ))
    if [ "$rc" -eq 0 ]; then
      : > "/state/$marker"
      own "/state/$marker"
      say "pass $step (${took}s)"
      break
    fi
    if [ "$SLEPT" = 1 ] && [ "$reran" = 0 ]; then
      reran=1
      say "$step failed (exit $rc) after a gap of over ${GAP}s (sleep or pause); rerunning once"
      continue
    fi
    case ",$flags," in
      *,net,*)
        if [ "$tries" -lt "$NET_TRIES" ]; then
          wait_s=$((NET_BACKOFF * tries))
          say "$step failed (exit $rc); it needs the network, retry $((tries + 1))/$NET_TRIES in ${wait_s}s"
          sleep "$wait_s"
          tries=$((tries + 1))
          continue
        fi ;;
    esac
    say "FAIL $step (exit $rc, ${took}s)"
    failed=$step
    break
  done
  [ -z "$failed" ] || break
done 3< /state/steps

if [ -n "$failed" ]; then
  printf '%s\n' "$failed" > /state/failed
  own /state/failed
  exit 1
fi
rm -f /state/failed
say "lane $LANE passed"
