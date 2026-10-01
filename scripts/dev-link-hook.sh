#!/usr/bin/env bash
# Development only: point the stable helper link (docs/decisions/0007-hook-location.md) at the locally
# built hook, so a Claude Code session with the plugin installed sends real events to a dev build.
#   scripts/dev-link-hook.sh          # link to .build/debug/agentville-hook
#   scripts/dev-link-hook.sh --remove # remove the link (hooks then exit 0 silently)
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$HOME/Library/Application Support/Agentville/bin"
link="$dir/agentville-hook"
if [ "${1:-}" = "--remove" ]; then
  rm -f "$link"; rmdir "$dir" "$(dirname "$dir")" 2>/dev/null || true
  echo "removed $link"; exit 0
fi
scripts/swift.sh build --product agentville-hook >/dev/null
mkdir -p "$dir"
ln -sfn "$PWD/.build/debug/agentville-hook" "$link"
echo "linked $link -> $PWD/.build/debug/agentville-hook"
