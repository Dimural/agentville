#!/usr/bin/env bash
# Non-negotiable #7: no networking. Fails if any networking API, framework, remote package
# dependency or network entitlement appears in the source tree.
# Usage: scripts/check-no-network.sh [--self-test]
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERNS=(
  'import[[:space:]]+Network\b'
  'import[[:space:]]+WebKit\b'
  'import[[:space:]]+CFNetwork\b'
  '\bURLSession\b'
  '\bURLRequest\b'
  '\bNSURLConnection\b'
  '\bNWConnection\b'
  '\bNWListener\b'
  '\bNWBrowser\b'
  '\bNWPathMonitor\b'
  '\bCFSocketCreate'
  '\bCFStreamCreatePairWithSocketToHost'
  '\bAF_INET6?\b'
  '\bPF_INET6?\b'
  '\bgetaddrinfo\b'
  '\bgethostbyname\b'
  '\bWKWebView\b'
  '\bSCNetworkReachability'
  'Data\(contentsOf:[[:space:]]*URL\(string:'
)

scan() { # $1 = dir; prints offending lines, returns 1 if any
  local dir=$1 bad=0
  for p in "${PATTERNS[@]}"; do
    if grep -rEn --include='*.swift' --include='*.c' --include='*.h' --include='*.m' "$p" "$dir" 2>/dev/null; then bad=1; fi
  done
  # Remote package dependencies would pull in code we haven't audited.
  if [ -f "$dir/Package.swift" ] && grep -En '\.package\(' "$dir/Package.swift"; then bad=1; fi
  # Network entitlements.
  if grep -rEln 'com\.apple\.security\.network\.(client|server)' "$dir" --include='*.entitlements' --include='*.plist' 2>/dev/null; then bad=1; fi
  return $bad
}

if [ "${1:-}" = "--self-test" ]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/Sources"
  echo 'let s = 1' > "$tmp/Sources/ok.swift"
  scan "$tmp" >/dev/null || { echo "self-test: clean tree flagged"; exit 1; }
  for bad in 'import Network' 'let x = URLSession.shared' 'socket(AF_INET, SOCK_STREAM, 0)' 'getaddrinfo(nil,nil,nil,nil)'; do
    echo "$bad" > "$tmp/Sources/bad.swift"
    if scan "$tmp" >/dev/null; then echo "self-test: missed '$bad'"; exit 1; fi
  done
  rm "$tmp/Sources/bad.swift"
  printf 'let package = Package(dependencies: [.package(url: "x", from: "1.0.0")])\n' > "$tmp/Package.swift"
  if scan "$tmp" >/dev/null; then echo "self-test: missed remote package"; exit 1; fi
  echo "check-no-network self-test: ok"
  exit 0
fi

if scan . ; then
  echo "check-no-network: ok (no networking APIs, remote packages or network entitlements)"
else
  echo "check-no-network: FAILED. Networking is forbidden (docs/quality/non-negotiables.md #7)." >&2
  exit 1
fi
