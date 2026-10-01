#!/usr/bin/env bash
# Build everything (the hook integration tests need the built binary), then run all tests.
# Extra args go to `swift test`, e.g. scripts/test.sh --filter Privacy
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift.sh build
# Serial: the hook timing tests measure wall time and must not compete with other suites for CPU.
scripts/swift.sh test --no-parallel "$@"
