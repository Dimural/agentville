#!/usr/bin/env bash
# Footprint budget (docs/quality/performance-budget.md): binary sizes and linked frameworks.
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK_MAX=$((2 * 1024 * 1024))
APP_MAX=$((15 * 1024 * 1024))

scripts/swift.sh build -c release >/dev/null
bin=$(scripts/swift.sh build -c release --show-bin-path)
fail=0

size() { stat -f %z "$1"; }
check_size() { # name path max
  local s; s=$(size "$2")
  printf '  %-18s %8d KB  (budget %d KB)\n' "$1" $((s / 1024)) $(($3 / 1024))
  if [ "$s" -gt "$3" ]; then echo "  -> OVER BUDGET" >&2; fail=1; fi
}

echo "check-footprint:"
check_size agentville-hook "$bin/agentville-hook" $HOOK_MAX
check_size Agentville "$bin/Agentville" $APP_MAX

# No networking frameworks linked directly by our binaries (non-negotiable #7).
for b in agentville-hook Agentville; do
  if otool -L "$bin/$b" | grep -Ei 'Network\.framework|CFNetwork|WebKit'; then
    echo "  -> $b links a networking framework" >&2; fail=1
  fi
done
# The hook must not link AppKit/SwiftUI (startup time).
if otool -L "$bin/agentville-hook" | grep -Ei 'AppKit|SwiftUI|SpriteKit'; then
  echo "  -> agentville-hook links a UI framework" >&2; fail=1
fi

[ $fail -eq 0 ] && echo "check-footprint: ok" || { echo "check-footprint: FAILED" >&2; exit 1; }
