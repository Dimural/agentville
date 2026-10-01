#!/usr/bin/env bash
# Build everything (the hook integration tests need the built binary), then run all tests.
# Extra args go to `swift test`, e.g. scripts/test.sh --filter Privacy
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift.sh build
scripts/swift.sh test "$@"
