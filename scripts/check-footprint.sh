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

# The app bundle (scripts/bundle-app.sh): total size, no entitlements (non-negotiable #9), no
# Dock icon, and the helper where the link expects it (ADR 0007).
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
scripts/bundle-app.sh --out "$tmp" >/dev/null
app="$tmp/Agentville.app"
bundle_bytes=$(( $(du -sk "$app" | cut -f1) * 1024 ))
printf '  %-18s %8d KB  (budget %d KB)\n' Agentville.app $((bundle_bytes / 1024)) $((APP_MAX / 1024))
if [ "$bundle_bytes" -gt "$APP_MAX" ]; then echo "  -> OVER BUDGET" >&2; fail=1; fi
[ -x "$app/Contents/Helpers/agentville-hook" ] || { echo "  -> helper missing from Contents/Helpers" >&2; fail=1; }
[ "$(plutil -extract LSUIElement raw -o - "$app/Contents/Info.plist")" = "true" ] || { echo "  -> LSUIElement not set" >&2; fail=1; }
for b in "$app" "$app/Contents/Helpers/agentville-hook"; do
  if [ -n "$(codesign -d --entitlements - "$b" 2>/dev/null | tr -d '[:space:]')" ]; then
    echo "  -> $(basename "$b") has entitlements" >&2; fail=1
  fi
done

[ $fail -eq 0 ] && echo "check-footprint: ok" || { echo "check-footprint: FAILED" >&2; exit 1; }
