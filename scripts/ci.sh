#!/usr/bin/env bash
# Everything CI runs, runnable locally. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== guards: self-tests"; scripts/check-no-network.sh --self-test; scripts/check-no-disk-writes.sh --self-test
echo "== guards";             scripts/check-no-network.sh; scripts/check-no-disk-writes.sh; scripts/check-docs.sh
echo "== tests";              scripts/test.sh
echo "== footprint";          scripts/check-footprint.sh
if command -v claude >/dev/null 2>&1; then
  echo "== plugin validate"
  claude plugin validate ./Plugin/agentville
  claude plugin validate .
else
  echo "== plugin validate: skipped (claude CLI not installed)"
fi
echo "ci: all green"
