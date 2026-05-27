#!/bin/sh
# sanitisation-gate.sh - fail the build if any pattern from the patterns file
# matches anywhere in the tracked working tree. Per-repo invariants live in
# .sanitisation-patterns (extended-regex, one per line, blank lines and #
# comments ignored). Used by the check stage of the GitLab CI pipeline.

set -eu

PATTERNS_FILE="${1:-.sanitisation-patterns}"

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "sanitisation-gate: patterns file not found: $PATTERNS_FILE" >&2
    exit 2
fi

SELF=$(basename "$0")

# Build a single extended-regex from non-blank, non-comment lines.
REGEX=$(grep -Ev '^[[:space:]]*(#|$)' "$PATTERNS_FILE" | paste -sd '|' -)

if [ -z "$REGEX" ]; then
    echo "sanitisation-gate: patterns file has no patterns: $PATTERNS_FILE" >&2
    exit 2
fi

# Scan all git-tracked files except the patterns file and this script itself.
violations=$(
    git ls-files | while read -r f; do
        case "$f" in
            "$PATTERNS_FILE"|*/"$SELF")
                continue
                ;;
        esac
        [ -f "$f" ] || continue
        grep -EHn "$REGEX" "$f" || true
    done
)

if [ -n "$violations" ]; then
    echo "sanitisation-gate: forbidden patterns found:" >&2
    echo "$violations" >&2
    exit 1
fi

n_files=$(git ls-files | wc -l)
n_patterns=$(grep -cEv '^[[:space:]]*(#|$)' "$PATTERNS_FILE")
echo "sanitisation-gate: passed ($n_files files scanned, $n_patterns patterns)."
