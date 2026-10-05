#!/usr/bin/env bash
# Non-negotiable #3: quitting leaves nothing behind. Launches the real app with the crew out and
# sessions arriving, quits it by SIGTERM and by SIGINT, and checks that the process is gone within
# 5 s, that it started no child processes, and that its socket file was removed. Needs a GUI
# session (a Mac you're logged in to), so it isn't part of scripts/ci.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/swift.sh build >/dev/null
bin="$(scripts/swift.sh build --show-bin-path)"
app="$bin/Agentville"
replay="$bin/agentville-replay"

# A private socket, so a running copy of the app is left alone. sun_path is short: stay in /tmp.
dir="$(mktemp -d /tmp/agentville-quit.XXXXXX)"
sock="$dir/a.sock"
trap 'rm -rf "$dir"' EXIT
fail=0

for sig in TERM INT; do
  AGENTVILLE_SOCKET="$sock" "$app" --release-crew --no-welcome >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 50); do [[ -S "$sock" ]] && break; sleep 0.1; done
  if [[ ! -S "$sock" ]]; then echo "FAIL ($sig): the app never opened its socket"; kill -9 "$pid" 2>/dev/null; fail=1; continue; fi

  # Sessions drop in while the crew is out; quit mid-scene.
  "$replay" Tools/scenarios/demo-mix.jsonl --speed 4 --socket "$sock" >/dev/null
  sleep 1

  children="$(pgrep -P "$pid" || true)"
  kill -"$sig" "$pid"
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done

  if kill -0 "$pid" 2>/dev/null; then echo "FAIL ($sig): still running 5 s after SIG$sig"; kill -9 "$pid"; fail=1
  else echo "ok   ($sig): exited"; fi
  if [[ -n "$children" ]]; then echo "FAIL ($sig): started child processes: $children"; fail=1
  else echo "ok   ($sig): no child processes"; fi
  if [[ -e "$sock" ]]; then echo "FAIL ($sig): socket file left behind"; rm -f "$sock"; fail=1
  else echo "ok   ($sig): socket file removed"; fi
done

if [[ $fail -ne 0 ]]; then echo "check-quit-cleanup: FAILED"; exit 1; fi
echo "check-quit-cleanup: nothing left behind"
