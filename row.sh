#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
REPLACE=false
if [ "${1:-}" = "--dry" ]; then
  DRY_RUN=true
  shift
elif [ "${1:-}" = "--replace" ]; then
  REPLACE=true
  shift
fi

if [ -z "${1:-}" ]; then
  DRY_RUN=true
  TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([0-9][0-9]\)$/:\1/')
else
  TIMESTAMP="$1"
fi

# Validate timestamp format: YYYY-MM-DDTHH:MM:SS±HH:MM (ISO 8601 with colon in tz)
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'
if ! [[ "$TIMESTAMP" =~ $TS_RE ]]; then
  echo "ERROR: invalid timestamp format: $TIMESTAMP" >&2
  echo "Expected: YYYY-MM-DDTHH:MM:SS±HH:MM (e.g. 2026-06-06T08:22:31-07:00)" >&2
  exit 1
fi

YEAR="${TIMESTAMP:0:4}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROWS_FILE="$SCRIPT_DIR/rows.txt"

# Refuse exact duplicates of the last logged timestamp (catches accidental re-runs)
if [ "$DRY_RUN" = false ] && [ "$REPLACE" = false ]; then
  LAST_TS=$(grep "^[0-9]" "$ROWS_FILE" | tail -1)
  if [ "$LAST_TS" = "$TIMESTAMP" ]; then
    echo "ERROR: timestamp $TIMESTAMP is identical to the last logged entry" >&2
    echo "Use --replace to overwrite the previous entry, or change the timestamp." >&2
    exit 1
  fi
fi

# Count existing entries for this year
COUNT=$(grep -c "^${YEAR}-" "$ROWS_FILE" || true)
INSTANCE=$(printf "%03d" $((COUNT + 1)))

if [ "$REPLACE" = true ]; then
  # Undo last commit, remove last timestamp, add new one
  git -C "$SCRIPT_DIR" reset --hard HEAD~1
  sed -i '' -e '$ { /^$/d; }' "$ROWS_FILE"
  # Remove the last line (previous timestamp)
  sed -i '' -e '$ d' "$ROWS_FILE"
  echo "$TIMESTAMP" >> "$ROWS_FILE"
  echo "" >> "$ROWS_FILE"

  # Re-count after removal
  COUNT=$(grep -c "^${YEAR}-" "$ROWS_FILE" || true)
  INSTANCE=$(printf "%03d" $((COUNT)))

  git -C "$SCRIPT_DIR" add rows.txt
  git -C "$SCRIPT_DIR" commit -m "feat: Add row timestamp ${YEAR}-${INSTANCE}"
  git -C "$SCRIPT_DIR" push --force
elif [ "$DRY_RUN" = false ]; then
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

# Days in year (leap year check)
if (( YEAR % 4 == 0 && (YEAR % 100 != 0 || YEAR % 400 == 0) )); then
  DAYS_IN_YEAR=366
else
  DAYS_IN_YEAR=365
fi
DAYS_LEFT=$((DAYS_IN_YEAR - DAY_OF_YEAR))
PCT_THROUGH=$((DAY_OF_YEAR * 100 / DAYS_IN_YEAR))

# Recent activity — last 14 calendar days
echo ""
echo "--- Last 2 Weeks ---"
# Calculate running total (year_rows - day_of_year) for the day before the window
first_day=$(date -j -v-13d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
first_doy=$(date -j -f "%Y-%m-%d" "$first_day" "+%-j")
rows_up_to_before=$(awk -v d="$first_day" -v y="$YEAR" '$0 ~ "^"y"-" && $0 < d"T"' "$ROWS_FILE" | wc -l | tr -d ' ')
running_total=$((rows_up_to_before - (first_doy - 1)))

buffered_line=""
day_streak=0
row_streak=0
best_day_streak=0
best_row_streak=0
for i in $(seq 13 -1 0); do
  day=$(date -j -v-${i}d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
  dow=$(date -j -f "%Y-%m-%d" "$day" "+%a")
  count=$(grep -c "^${day}T" "$ROWS_FILE" || true)
  running_total=$((running_total + count - 1))
  if [ "$count" -gt 0 ]; then
    # Print any buffered line first
    if [ -n "$buffered_line" ]; then
      echo "$buffered_line"
    fi
    day_streak=$((day_streak + 1))
    row_streak=$((row_streak + count))
    pluses=$(printf '+%.0s' $(seq 1 $count))
    RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
    label="-${pluses}"
    pad=$((5 - ${#label}))
    spacing=$(printf '%*s' "$pad" "")
    colored="${RED}-${GRN}${pluses}${RST}"
    buffered_line=$(printf "%s %s %s%s%3d" "$dow" "$day" "$colored" "$spacing" "$running_total")
  else
    # Flush buffered row line with streak appended
    if [ -n "$buffered_line" ] && [ "$day_streak" -gt 0 ]; then
      if [ "$day_streak" -gt "$best_day_streak" ]; then best_day_streak=$day_streak; fi
      if [ "$row_streak" -gt "$best_row_streak" ]; then best_row_streak=$row_streak; fi
      GRN=$'\033[32m'; RST=$'\033[0m'
      printf "%s  streak: %dd %dr  Highscores: %s%dd %dr%s\n" "$buffered_line" "$day_streak" "$row_streak" "$GRN" "$best_day_streak" "$best_row_streak" "$RST"
    elif [ -n "$buffered_line" ]; then
      echo "$buffered_line"
    fi
    buffered_line=""
    day_streak=0
    row_streak=0
    RED=$'\033[31m'; RST=$'\033[0m'
    printf "%s %s %s-%s    %3d\n" "$dow" "$day" "$RED" "$RST" "$running_total"
  fi
done
# Flush any remaining buffered line (active streak, no ending yet)
if [ -n "$buffered_line" ]; then
  echo "$buffered_line"
fi

# Current contiguous row streak (individual instances; resets on missed day)
COUNT_STREAK=0
PREV_DAY=""
while IFS= read -r entry; do
  entry_day="${entry:0:10}"
  if [ -z "$PREV_DAY" ]; then
    PREV_DAY="$entry_day"
    COUNT_STREAK=1
  else
    EXPECTED=$(date -j -v-1d -f "%Y-%m-%d" "$PREV_DAY" "+%Y-%m-%d")
    if [ "$entry_day" = "$PREV_DAY" ]; then
      COUNT_STREAK=$((COUNT_STREAK + 1))
    elif [ "$entry_day" = "$EXPECTED" ]; then
      COUNT_STREAK=$((COUNT_STREAK + 1))
      PREV_DAY="$entry_day"
    else
      break
    fi
  fi
done < <(grep "^[0-9]" "$ROWS_FILE" | sort -r)

# Current day streak (consecutive days with at least one row)
DAY_STREAK=0
STREAK_DATE="${TIMESTAMP:0:10}"
while grep -q "^${STREAK_DATE}T" "$ROWS_FILE"; do
  DAY_STREAK=$((DAY_STREAK + 1))
  STREAK_DATE=$(date -j -v-1d -f "%Y-%m-%d" "$STREAK_DATE" "+%Y-%m-%d")
done

# Days rowed and missed this year
DAYS_ROWED=$(grep "^${YEAR}-" "$ROWS_FILE" | cut -c1-10 | sort -u | wc -l | tr -d ' ')
DAYS_MISSED=$((DAY_OF_YEAR - DAYS_ROWED))

echo ""
echo "--- Row Stats ---"
echo "Row #${ROW_NUM} of ${YEAR}"
echo "Day #${DAY_OF_YEAR} of ${DAYS_IN_YEAR} (${PCT_THROUGH}% through ${YEAR}, ${DAYS_LEFT} days left)"
echo "Days rowed: ${DAYS_ROWED} | Days missed: ${DAYS_MISSED}"
echo "Day streak: ${DAY_STREAK} | Row streak: ${COUNT_STREAK}"
if [ "$DIFF" -gt 0 ]; then
  echo "📈 ${DIFF} rows ahead of pace (1/day)"
elif [ "$DIFF" -lt 0 ]; then
  echo "📉 $((-DIFF)) rows behind pace (1/day)"
else
  echo "📊 Exactly on pace (1/day)"
fi
