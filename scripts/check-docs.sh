#!/usr/bin/env bash
# Every relative Markdown link in the repo's docs must resolve to an existing file.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
while IFS= read -r md; do
  dir=$(dirname "$md")
  # Extract (target) from [text](target); skip URLs and pure anchors.
  { grep -oE '\]\([^)#[:space:]]+(#[^)]*)?\)' "$md" || true; } | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' | while IFS= read -r t; do
    case "$t" in http*|mailto:*|"") continue ;; esac
    if [ ! -e "$dir/$t" ]; then echo "$md: broken link -> $t"; echo x >> "${TMPDIR:-/tmp}/av-docs-fail.$$"; fi
  done
done < <(find . -name '*.md' -not -path './.build/*' -not -name 'PROJECT_BRIEF.md' | sort)
if [ -f "${TMPDIR:-/tmp}/av-docs-fail.$$" ]; then rm -f "${TMPDIR:-/tmp}/av-docs-fail.$$"; echo "check-docs: FAILED" >&2; exit 1; fi
echo "check-docs: ok (all relative links resolve)"
