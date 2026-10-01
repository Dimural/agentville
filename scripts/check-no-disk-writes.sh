#!/usr/bin/env bash
# Non-negotiables #4 and #8: nothing written to disk except preferences (and the user-initiated
# install artefacts), no event logs, and the hook never writes to stdout/stderr.
# Files allowed to use file-writing APIs are listed in scripts/disk-write-allowlist.txt.
# Usage: scripts/check-no-disk-writes.sh [--self-test]
set -euo pipefail
cd "$(dirname "$0")/.."

WRITE_PATTERNS=(
  '\.write\(to:'
  '\.write\(toFile:'
  'createFile\(atPath:'
  'FileHandle\(forWritingAtPath:'
  'FileHandle\(forUpdatingAtPath:'
  'FileHandle\(forWritingTo:'
  'createDirectory\('
  'createSymbolicLink\('
  'copyItem\('
  'moveItem\('
  '\bfopen\('
  'O_CREAT'
  '\bos_log\('
  '\bLogger\('
  '\bNSLog\('
  'OSLog\('
  '\bUserDefaults\b'
)
# Code that runs inside Claude Code's hook must be silent: no stdout/stderr output at all.
SILENT_DIRS=(Sources/agentville-hook Sources/AgentvilleWire Sources/AgentvilleCore)
SILENT_PATTERNS=('\bprint\(' 'FileHandle\.standardOutput' 'FileHandle\.standardError' '\bputs\(' '\bdebugPrint\(' '\bdump\(' 'STDOUT_FILENO' 'STDERR_FILENO')

scan() { # $1 = root; $2 = allowlist file
  local root=$1 allow=$2 bad=0
  local files
  files=$(cd "$root" && find Sources -name '*.swift' 2>/dev/null | sort)
  for f in $files; do
    if [ -f "$allow" ] && grep -qxF "$f" "$allow"; then continue; fi
    case "$f" in Sources/agentville-replay/*) continue ;; esac # dev tool: prints to the terminal, writes no files
    for p in "${WRITE_PATTERNS[@]}"; do
      if grep -En "$p" "$root/$f" | grep -vE '^[0-9]+:[[:space:]]*//' | sed "s|^|$f:|"; then bad=1; fi
    done
  done
  for d in "${SILENT_DIRS[@]}"; do
    [ -d "$root/$d" ] || continue
    for p in "${SILENT_PATTERNS[@]}"; do
      if grep -rEn "$p" "$root/$d" --include='*.swift' | grep -vE ':[0-9]+:[[:space:]]*//'; then bad=1; fi
    done
  done
  return $bad
}

if [ "${1:-}" = "--self-test" ]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/Sources/Agentville" "$tmp/Sources/agentville-hook"
  printf 'let a = 1\n// .write(to: is fine in a full-line comment\n' > "$tmp/Sources/Agentville/ok.swift"
  scan "$tmp" "$tmp/allow.txt" >/dev/null || { echo "self-test: clean tree flagged"; exit 1; }
  for bad in 'try data.write(to: url)' 'Logger(subsystem: "x", category: "y")' 'UserDefaults.standard.set(1, forKey: "k")'; do
    echo "$bad" > "$tmp/Sources/Agentville/bad.swift"
    if scan "$tmp" "$tmp/allow.txt" >/dev/null; then echo "self-test: missed '$bad'"; exit 1; fi
  done
  echo "Sources/Agentville/bad.swift" > "$tmp/allow.txt"
  scan "$tmp" "$tmp/allow.txt" >/dev/null || { echo "self-test: allowlist ignored"; exit 1; }
  echo 'print("hi")' > "$tmp/Sources/agentville-hook/main.swift"
  if scan "$tmp" "$tmp/allow.txt" >/dev/null; then echo "self-test: missed print in hook"; exit 1; fi
  echo "check-no-disk-writes self-test: ok"
  exit 0
fi

if scan . scripts/disk-write-allowlist.txt; then
  echo "check-no-disk-writes: ok (file writes only in allowlisted files; hook and core are silent)"
else
  echo "check-no-disk-writes: FAILED. See docs/quality/non-negotiables.md #4 and #8; allowlist: scripts/disk-write-allowlist.txt" >&2
  exit 1
fi
