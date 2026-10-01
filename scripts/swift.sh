#!/usr/bin/env bash
# Wraps `swift` so it works with full Xcode *or* the Command Line Tools alone.
# If Xcode's toolchain is unusable (e.g. licence not accepted), fall back to the CLT and add the
# Swift Testing framework paths the CLT doesn't put on the default search path.
set -euo pipefail

CLT=/Library/Developer/CommandLineTools
extra=()

if ! swift --version >/dev/null 2>&1; then
  if [ -x "$CLT/usr/bin/swift" ]; then
    export DEVELOPER_DIR="$CLT"
  else
    echo "error: no usable Swift toolchain. Install Xcode or the Command Line Tools." >&2
    exit 1
  fi
fi

if [ "${DEVELOPER_DIR:-}" = "$CLT" ] && [ "${1:-}" = "test" ]; then
  F="$CLT/Library/Developer/Frameworks"
  L="$CLT/Library/Developer/usr/lib"
  extra=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc "-F$F" -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L")
fi

exec swift "$@" ${extra[@]+"${extra[@]}"}
