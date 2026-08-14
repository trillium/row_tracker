#!/usr/bin/env bash
set -euo pipefail

# ── Streak computation: the rest-day bank rule ───────────────────────────────
# Extra effort earlier in a streak buys forgiveness for a single missed day.
#
#   * Every row beyond the first on one calendar day deposits ONE credit
#     (two rows in a day = 1 credit, three rows = 2 credits, ...).
#   * A calendar day with zero rows WITHDRAWS one credit and the streak carries
#     through that day unbroken (a "covered" rest day).
#   * The balance may never go negative: an empty bank plus a missed day breaks
#     the streak exactly as it always did. There is no cap on the balance.
#   * Credits are earned and spent within a single streak — when a streak
#     breaks, the bank resets to zero along with the streak.
#   * A covered rest day keeps the streak ALIVE but is not itself a rowing day,
#     so it does NOT increment the day streak and does NOT change the row streak.
#
# _streak_step applies one calendar day to the running state held in the globals
# _ds (day streak), _rs (row streak) and _bank (rest-day balance). Every place
# that walks the log — the two live views and the 2-week history — routes each
# day through this one function so they can never disagree about a covered day.
_streak_step() {
  local count="$1"
  if [ "$count" -gt 0 ]; then
    if [ "$_ds" -eq 0 ]; then
      _ds=1
      _rs="$count"
    else
      _ds=$((_ds + 1))
      _rs=$((_rs + count))
    fi
    # Deposit one credit for every row beyond the first on this day.
    _bank=$((_bank + count - 1))
  elif [ "$_ds" -gt 0 ] && [ "$_bank" -gt 0 ]; then
    # Covered rest day: spend one credit, the streak holds. Balance stays >= 0.
    _bank=$((_bank - 1))
  else
    # Empty bank (or no active streak): the streak breaks and the bank resets.
    _ds=0
    _rs=0
    _bank=0
  fi
}

# compute_streaks <rows_file> <as_of_date YYYY-MM-DD>
# Walks the whole log forward, applying the rest-day bank rule day by day, and
# echoes "<day_streak> <row_streak>" for the streak that is current as of the
# given date. Forward order is load-bearing: a credit can only cover a miss that
# comes AFTER it was banked, so we must never process the log backwards here.
compute_streaks() {
  local rows_file="$1" as_of="$2"
  local _ds=0 _rs=0 _bank=0
  local prev_day="" cnt day d
  # Chronological list of "<count> <YYYY-MM-DD>" — one line per rowed calendar day.
  while read -r cnt day; do
    if [ -n "$prev_day" ]; then
      # Every calendar day strictly between two rowed days is a miss.
      d=$(date -j -v+1d -f "%Y-%m-%d" "$prev_day" "+%Y-%m-%d")
      while [[ "$d" < "$day" ]]; do
        _streak_step 0
        d=$(date -j -v+1d -f "%Y-%m-%d" "$d" "+%Y-%m-%d")
      done
    fi
    _streak_step "$cnt"
    prev_day="$day"
  done < <(grep "^[0-9]" "$rows_file" | cut -c1-10 | sort | uniq -c || true)

  # Fully-elapsed missed days between the last rowed day and the as-of date
  # (e.g. a dry run taken some days later) also spend from or break the streak.
  if [ -n "$prev_day" ]; then
    d=$(date -j -v+1d -f "%Y-%m-%d" "$prev_day" "+%Y-%m-%d")
    while [[ "$d" < "$as_of" ]]; do
      _streak_step 0
      d=$(date -j -v+1d -f "%Y-%m-%d" "$d" "+%Y-%m-%d")
    done
  fi

  echo "$_ds $_rs"
}

# ── Subcommand dispatch ──────────────────────────────────────────────────────
# row.sh treats $1 as a timestamp by default. Reserved words branch first;
# anything else falls through to the existing log-a-row behavior below.
#
# `row pomodoro` reads the Talon Pomodoro timer's wall-clock state and prints
# the end time + remaining. The state file is owned/written by the Talon side
# (pomodoro.py) per the shared contract; row only READS it.
#   File:  ~/.talon/pomodoro-state.json
#   Shape: {"active": bool, "end_iso": "...", "end_epoch": N, "paused": bool}
if [ "${1:-}" = "pomodoro" ]; then
  shift
  POMODORO_STATE="${HOME}/.talon/pomodoro-state.json"

  fmt_remaining() {
    # $1 = seconds -> "MMm SSs"
    printf "%dm %02ds" $(($1 / 60)) $(($1 % 60))
  }

  if [ ! -f "$POMODORO_STATE" ]; then
    echo "No active pomodoro. (Start one from Talon: \"pomodoro start\")"
    exit 0
  fi

  ACTIVE=$(grep -o '"active"[[:space:]]*:[[:space:]]*\(true\|false\)' "$POMODORO_STATE" | grep -o '\(true\|false\)$' || true)
  PAUSED=$(grep -o '"paused"[[:space:]]*:[[:space:]]*\(true\|false\)' "$POMODORO_STATE" | grep -o '\(true\|false\)$' || true)
  END_ISO=$(grep -o '"end_iso"[[:space:]]*:[[:space:]]*"[^"]*"' "$POMODORO_STATE" | sed 's/.*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
  END_EPOCH=$(grep -o '"end_epoch"[[:space:]]*:[[:space:]]*[0-9]*' "$POMODORO_STATE" | grep -o '[0-9]*$' || true)

  if [ "$ACTIVE" != "true" ]; then
    echo "No active pomodoro. (Start one from Talon: \"pomodoro start\")"
    exit 0
  fi

  if [ -z "$END_EPOCH" ]; then
    echo "ERROR: pomodoro is active but $POMODORO_STATE has no end_epoch" >&2
    exit 1
  fi

  NOW=$(date +%s)
  REM=$((END_EPOCH - NOW))

  if [ "$PAUSED" = "true" ]; then
    if [ "$REM" -gt 0 ]; then
      echo "⏸️  Pomodoro paused — ends ${END_ISO} ($(fmt_remaining "$REM") remaining when resumed)"
    else
      echo "⏸️  Pomodoro paused — ${END_ISO}"
    fi
  elif [ "$REM" -gt 0 ]; then
    echo "🍅 Pomodoro active — ends ${END_ISO} ($(fmt_remaining "$REM") remaining)"
  else
    echo "🍅 Pomodoro ended ${END_ISO} ($(fmt_remaining $((-REM))) ago)"
  fi
  exit 0
fi
# ─────────────────────────────────────────────────────────────────────────────

# `row post-slack` posts the stats for the LAST already-logged row to Slack
# again, without appending a timestamp or making a git commit. Useful when a
# post failed or you want a re-post of the current standing.
if [ "${1:-}" = "post-slack" ]; then
  shift
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROWS_FILE="$SCRIPT_DIR/rows.txt"
  SLACK_CREDS="$SCRIPT_DIR/.slack-creds"

  TIMESTAMP=$(grep "^[0-9]" "$ROWS_FILE" | tail -1)
  if [ -z "$TIMESTAMP" ]; then
    echo "ERROR: no rows logged yet in $ROWS_FILE" >&2
    exit 1
  fi
  YEAR="${TIMESTAMP:0:4}"

  # ROW_NUM is the count itself here (not COUNT+1) — TIMESTAMP is already
  # the last logged row, so it IS row number COUNT, not the next one.
  ROW_NUM=$(grep -c "^${YEAR}-" "$ROWS_FILE" || true)
  DAY_OF_YEAR=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%-j" 2>/dev/null || date -j -f "%Y-%m-%dT%T" "${TIMESTAMP:0:19}" "+%-j")
  DIFF=$((ROW_NUM - DAY_OF_YEAR))

  if (( YEAR % 4 == 0 && (YEAR % 100 != 0 || YEAR % 400 == 0) )); then
    DAYS_IN_YEAR=366
  else
    DAYS_IN_YEAR=365
  fi
  PCT_THROUGH=$((DAY_OF_YEAR * 100 / DAYS_IN_YEAR))

  # Current streaks (day + row) under the rest-day bank rule. TIMESTAMP here is
  # the last logged row, so its date is the as-of day.
  read -r DAY_STREAK COUNT_STREAK < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

  echo "--- Row Stats (last logged row — no new entry made) ---"
  echo "Row #${ROW_NUM} of ${YEAR}"
  echo "Day #${DAY_OF_YEAR} of ${DAYS_IN_YEAR} (${PCT_THROUGH}% through ${YEAR})"
  echo "Day streak: ${DAY_STREAK} | Row streak: ${COUNT_STREAK}"

  if [ "$DIFF" -gt 0 ]; then
    PACE_PART="📈 ${DIFF} ahead"
  elif [ "$DIFF" -lt 0 ]; then
    PACE_PART="📉 $((-DIFF)) behind"
  else
    PACE_PART="📊 on pace"
  fi

  if [ "$COUNT_STREAK" -gt 0 ]; then
    STREAK_PART=" · 🔥 ${DAY_STREAK}day ${COUNT_STREAK}row streak"
  else
    STREAK_PART=""
  fi

  MSG="🚣 Row ${ROW_NUM}/${DAYS_IN_YEAR} · 📅 Day ${DAY_OF_YEAR}/${DAYS_IN_YEAR} (${PCT_THROUGH}%) · ${PACE_PART}${STREAK_PART}"

  echo ""
  echo "--- Slack post ---"
  echo "→ $MSG"

  if [ ! -f "$SLACK_CREDS" ]; then
    echo "ERROR: $SLACK_CREDS not found — cannot post to Slack" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  set -a; . "$SLACK_CREDS"; set +a

  SLACK_RESP=$(curl -s --max-time 5 -X POST "${SLACK_API_BASE}/chat.postMessage" \
    -H "Cookie: $SLACK_COOKIE" \
    --data-urlencode "token=$SLACK_TOKEN" \
    --data-urlencode "channel=$SLACK_CHANNEL" \
    --data-urlencode "text=$MSG" 2>&1) || SLACK_RESP="curl_error"

  if echo "$SLACK_RESP" | grep -q '"ok":true'; then
    echo "✓ posted to #${SLACK_CHANNEL_NAME}"
  else
    echo "✗ slack post failed: $(echo "$SLACK_RESP" | head -c 200)"
  fi
  exit 0
fi
# ─────────────────────────────────────────────────────────────────────────────

DRY_RUN=false
REPLACE=false
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat << 'EOF'
row — rowing tracker with Slack integration

USAGE:
  row [OPTIONS] [TIMESTAMP]
  row SUBCOMMAND

OPTIONS:
  --help, -h         Show this help message
  --dry              Show stats without logging (default if no timestamp given)
  --replace          Replace last logged entry with new timestamp

TIMESTAMP FORMAT:
  YYYY-MM-DDTHH:MM:SS±HH:MM  (ISO 8601 with timezone)
  Example: 2026-06-06T08:22:31-07:00

SUBCOMMANDS:
  pomodoro           Show current Pomodoro timer state
  post-slack         Post last row's stats to Slack without logging

EXAMPLES:
  row                              # Dry run with current time
  row 2026-07-26T19:20:05-07:00   # Log a row for specific timestamp
  row now                          # Log current time
  row --replace 2026-07-26T19:20:05-07:00  # Replace last entry
  row --dry                        # Dry run (same as no args)
  row pomodoro                     # Show Pomodoro state
  row post-slack                   # Post to Slack
EOF
  exit 0
elif [ "${1:-}" = "--dry" ]; then
  DRY_RUN=true
  shift
elif [ "${1:-}" = "--replace" ]; then
  REPLACE=true
  shift
fi

if [ -z "${1:-}" ]; then
  DRY_RUN=true
  TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([0-9][0-9]\)$/:\1/')
elif [ "${1:-}" = "now" ]; then
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

# Validation: reject duplicates (anywhere in file) and timestamps older than the last entry
if [ "$DRY_RUN" = false ] && [ "$REPLACE" = false ]; then
  if grep -qFx "$TIMESTAMP" "$ROWS_FILE"; then
    echo "ERROR: timestamp $TIMESTAMP already exists in rows.txt" >&2
    echo "Use --replace to overwrite the previous entry, or change the timestamp." >&2
    exit 1
  fi
  LAST_TS=$(grep "^[0-9]" "$ROWS_FILE" | tail -1)
  if [ -n "$LAST_TS" ]; then
    ts_to_epoch() {
      local ts="$1"
      date -j -f "%Y-%m-%dT%H:%M:%S%z" "${ts:0:22}${ts:23:2}" "+%s" 2>/dev/null
    }
    NEW_EPOCH=$(ts_to_epoch "$TIMESTAMP")
    LAST_EPOCH=$(ts_to_epoch "$LAST_TS")
    if [ -n "$NEW_EPOCH" ] && [ -n "$LAST_EPOCH" ] && [ "$NEW_EPOCH" -lt "$LAST_EPOCH" ]; then
      echo "ERROR: timestamp $TIMESTAMP is older than last logged entry $LAST_TS" >&2
      echo "Refusing to insert out-of-order timestamp. Use --replace to overwrite the last entry." >&2
      exit 1
    fi
  fi
fi

# Count existing entries for this year
COUNT=$(grep -c "^${YEAR}-" "$ROWS_FILE" || true)
INSTANCE=$(printf "%03d" $((COUNT + 1)))

if [ "$REPLACE" = true ]; then
  # Undo last commit (this already removes its timestamp line from rows.txt
  # via the working-tree checkout), then just strip the trailing blank line
  # before appending the replacement. Do NOT delete another line here —
  # reset --hard already did that; doing it twice eats the prior entry.
  git -C "$SCRIPT_DIR" reset --hard HEAD~1
  sed -i '' -e '$ { /^$/d; }' "$ROWS_FILE"
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

# Streak state for the window walks through the same _streak_step rule as the
# headline number, so a covered rest day is treated identically in both. The
# bank is tallied within this 14-day window (credits earned earlier still cover
# the miss they were banked before, which is all the rule requires).
buffered_line=""
_ds=0
_rs=0
_bank=0
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
    _streak_step "$count"
    pluses=$(printf '+%.0s' $(seq 1 $count))
    RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
    label="-${pluses}"
    pad=$((5 - ${#label}))
    spacing=$(printf '%*s' "$pad" "")
    colored="${RED}-${GRN}${pluses}${RST}"
    buffered_line=$(printf "%s %s %s%s%3d" "$dow" "$day" "$colored" "$spacing" "$running_total")
  elif [ "$_ds" -gt 0 ] && [ "$_bank" -gt 0 ]; then
    # Covered rest day: spend a credit, the streak holds through unbroken. Flush
    # the buffered rowing line first so the rest day prints after it, then keep
    # the streak alive (no reset, day/row streak unchanged).
    if [ -n "$buffered_line" ]; then
      echo "$buffered_line"
      buffered_line=""
    fi
    _streak_step 0
    YEL=$'\033[33m'; RST=$'\033[0m'
    printf "%s %s %s~%s    %3d  (rest — streak held, bank %d)\n" "$dow" "$day" "$YEL" "$RST" "$running_total" "$_bank"
  else
    # Missed day with an empty bank: the streak breaks. Flush buffered row line
    # with the ended streak + highscores appended.
    if [ -n "$buffered_line" ] && [ "$_ds" -gt 0 ]; then
      if [ "$_ds" -gt "$best_day_streak" ]; then best_day_streak=$_ds; fi
      if [ "$_rs" -gt "$best_row_streak" ]; then best_row_streak=$_rs; fi
      GRN=$'\033[32m'; RST=$'\033[0m'
      printf "%s  streak: %dd %dr  Highscores: %s%dd %dr%s\n" "$buffered_line" "$_ds" "$_rs" "$GRN" "$best_day_streak" "$best_row_streak" "$RST"
    elif [ -n "$buffered_line" ]; then
      echo "$buffered_line"
    fi
    buffered_line=""
    _streak_step 0   # resets _ds/_rs/_bank
    RED=$'\033[31m'; RST=$'\033[0m'
    printf "%s %s %s-%s    %3d\n" "$dow" "$day" "$RED" "$RST" "$running_total"
  fi
done
# Flush any remaining buffered line (active streak, no ending yet)
if [ -n "$buffered_line" ]; then
  echo "$buffered_line"
fi

# Current streaks (day + row) under the rest-day bank rule
read -r DAY_STREAK COUNT_STREAK < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

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

# Post to Slack (skipped on --dry, --replace, or when creds file is missing)
SLACK_CREDS="$SCRIPT_DIR/.slack-creds"
if [ "$DRY_RUN" = false ] && [ "$REPLACE" = false ] && [ -f "$SLACK_CREDS" ]; then
  # shellcheck source=/dev/null
  set -a; . "$SLACK_CREDS"; set +a

  if [ "$DIFF" -gt 0 ]; then
    PACE_PART="📈 ${DIFF} ahead"
  elif [ "$DIFF" -lt 0 ]; then
    PACE_PART="📉 $((-DIFF)) behind"
  else
    PACE_PART="📊 on pace"
  fi

  if [ "${COUNT_STREAK:-0}" -gt 0 ]; then
    STREAK_PART=" · 🔥 ${DAY_STREAK}day ${COUNT_STREAK}row streak"
  else
    STREAK_PART=""
  fi

  MSG="🚣 Row ${ROW_NUM}/${DAYS_IN_YEAR} · 📅 Day ${DAY_OF_YEAR}/${DAYS_IN_YEAR} (${PCT_THROUGH}%) · ${PACE_PART}${STREAK_PART}"

  echo ""
  echo "--- Slack post ---"
  echo "→ $MSG"
  SLACK_RESP=$(curl -s --max-time 5 -X POST "${SLACK_API_BASE}/chat.postMessage" \
    -H "Cookie: $SLACK_COOKIE" \
    --data-urlencode "token=$SLACK_TOKEN" \
    --data-urlencode "channel=$SLACK_CHANNEL" \
    --data-urlencode "text=$MSG" 2>&1) || SLACK_RESP="curl_error"

  if echo "$SLACK_RESP" | grep -q '"ok":true'; then
    echo "✓ posted to #${SLACK_CHANNEL_NAME}"
  else
    echo "✗ slack post failed: $(echo "$SLACK_RESP" | head -c 200)"
  fi
fi
