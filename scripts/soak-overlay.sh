#!/usr/bin/env bash
# Soak harness for bug 0001 (docs/bugs/0001-grey-screen-overlay.md): the screen turned flat grey
# while the crew's overlay was up. Runs private copies of the release app with the crew out under a
# steady event load and watches their overlay windows (Tools/soak/overlay-probe.swift), flagging any
# frame that is mostly opaque. Also collects each copy's diagnostics (`--diagnostics-stderr`) so a
# watchdog trip ("overlay hidden") shows up even if the probe misses the moment.
#
# Usage: scripts/soak-overlay.sh [--minutes 10] [--copies 2] [--rate 200]
# Needs a logged-in Mac and Screen Recording permission for the terminal. Not part of scripts/ci.sh.
# The crew will be out on your screen while it runs. Each copy uses its own socket, so a running
# Agentville is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

minutes=10 copies=2 rate=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minutes) minutes="$2"; shift 2 ;;
    --copies) copies="$2"; shift 2 ;;
    --rate) rate="$2"; shift 2 ;;
    *) echo "usage: $0 [--minutes M] [--copies N] [--rate R]" >&2; exit 2 ;;
  esac
done
seconds=$(( minutes * 60 ))

scripts/swift.sh build -c release >/dev/null
bin="$(scripts/swift.sh build -c release --show-bin-path)"
# sun_path is short: stay in /tmp.
dir="$(mktemp -d /tmp/agentville-soak.XXXXXX)"
DEVELOPER_DIR="${DEVELOPER_DIR:-}" swiftc -O Tools/soak/overlay-probe.swift -o "$dir/overlay-probe" 2>/dev/null \
  || DEVELOPER_DIR=/Library/Developer/CommandLineTools swiftc -O Tools/soak/overlay-probe.swift -o "$dir/overlay-probe"

pids=() feeders=()
cleanup() {
  for p in ${feeders[@]+"${feeders[@]}"}; do kill "$p" 2>/dev/null || true; done
  for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq "$copies"); do
  sock="$dir/s$i.sock"
  AGENTVILLE_SOCKET="$sock" "$bin/Agentville" --release-crew --no-welcome --diagnostics-stderr 2>"$dir/diag-$i.txt" >/dev/null &
  pids+=($!)
  for _ in $(seq 50); do [[ -S "$sock" ]] && break; sleep 0.1; done
  # A steady load: 100 sessions at $rate events/s, repeated until the soak ends.
  ( end=$((SECONDS + seconds)); while (( SECONDS < end )); do
      "$bin/agentville-replay" --generate hundred --seconds 60 --rate "$rate" --socket "$sock" >/dev/null 2>&1 || sleep 1
    done ) &
  feeders+=($!)
done

echo "soak: $copies copies, $minutes min, $rate events/s each; output in $dir"
status=0
"$dir/overlay-probe" --pids "$(IFS=,; echo "${pids[*]}")" --seconds "$seconds" --interval 1 --out "$dir" || status=1

trips=$(cat "$dir"/diag-*.txt | grep -c "overlay hidden" || true)
echo "watchdog trips: $trips"
for i in $(seq "$copies"); do
  if ! kill -0 "${pids[$((i - 1))]}" 2>/dev/null; then echo "copy $i exited early"; status=1; fi
done
if [[ $trips -gt 0 ]]; then grep -h "overlay hidden\|display\|first frame" "$dir"/diag-*.txt | head -40; status=1; fi
if [[ $status -eq 0 ]]; then echo "soak-overlay: no opaque frame, no stall"; rm -rf "$dir"
else echo "soak-overlay: SOMETHING TO LOOK AT; kept $dir"; fi
exit $status
