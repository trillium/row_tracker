#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry" ]; then
  DRY_RUN=true
  shift
fi

if [ -z "${1:-}" ]; then
  echo "Usage: ./row.sh [--dry] <timestamp>" >&2
  echo "Example: ./row.sh \"2026-03-01T10:44:56-08:00\"" >&2
  echo "         ./row.sh --dry \"2026-03-01T10:44:56-08:00\"" >&2
  exit 1
fi

TIMESTAMP="$1"
YEAR="${TIMESTAMP:0:4}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROWS_FILE="$SCRIPT_DIR/rows.txt"

# Count existing entries for this year
COUNT=$(grep -c "^${YEAR}-" "$ROWS_FILE" || true)
INSTANCE=$(printf "%03d" $((COUNT + 1)))

if [ "$DRY_RUN" = false ]; then
  # Append timestamp before the trailing empty line
  # Remove trailing newline, append timestamp, restore trailing newline
  sed -i '' -e '$ { /^$/d; }' "$ROWS_FILE"
  echo "$TIMESTAMP" >> "$ROWS_FILE"
  echo "" >> "$ROWS_FILE"

  # Commit and push
  git -C "$SCRIPT_DIR" add rows.txt
  git -C "$SCRIPT_DIR" commit -m "feat: Add row timestamp ${YEAR}-${INSTANCE}"
  git -C "$SCRIPT_DIR" push
fi

# Stats
ROW_NUM=$((COUNT + 1))
DAY_OF_YEAR=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%-j" 2>/dev/null || date -j -f "%Y-%m-%dT%T" "${TIMESTAMP:0:19}" "+%-j")
DIFF=$((ROW_NUM - DAY_OF_YEAR))

echo ""
echo "--- Row Stats ---"
echo "Row #${ROW_NUM} of ${YEAR}"
echo "Day #${DAY_OF_YEAR} of ${YEAR}"
if [ "$DIFF" -gt 0 ]; then
  echo "📈 ${DIFF} rows ahead of pace (1/day)"
elif [ "$DIFF" -lt 0 ]; then
  echo "📉 $((-DIFF)) rows behind pace (1/day)"
else
  echo "📊 Exactly on pace (1/day)"
fi
