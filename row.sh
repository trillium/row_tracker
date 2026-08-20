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
#   * When a streak breaks and a new one begins, the new streak INHERITS the
#     total credits earned by the most recently completed streak — so doubles
#     banked before a break continue to cover rest days in the streak that
#     follows. Credits from the new streak also accumulate on top.
#   * A covered rest day keeps the streak ALIVE but is not itself a rowing day,
#     so it does NOT increment the day streak and does NOT change the row streak.
#
# _streak_step applies one calendar day to the running state held in the globals
# _ds (day streak), _rs (row streak), _bank (rest-day balance),
# _prev_streak_credits (credits earned by the last completed streak, carried
# into the next one), and _cur_streak_credits (credits earned so far in the
# current streak). Every place that walks the log — the live views and the
# 2-week history — routes each day through this one function.
_streak_step() {
  local count="$1"
  if [ "$count" -gt 0 ]; then
    if [ "$_ds" -eq 0 ]; then
      # New streak: inherit credits earned during the most recently completed streak.
      _ds=1
      _rs="$count"
      _bank=$((_prev_streak_credits + count - 1))
      _cur_streak_credits=$((count - 1))
      _prev_streak_credits=0
    else
      _ds=$((_ds + 1))
      _rs=$((_rs + count))
      _bank=$((_bank + count - 1))
      _cur_streak_credits=$((_cur_streak_credits + count - 1))
    fi
  elif [ "$_ds" -gt 0 ] && [ "$_bank" -gt 0 ]; then
    # Covered rest day: spend one credit, the streak holds.
    _bank=$((_bank - 1))
    _ds=$((_ds + 1))
  else
    # Empty bank (or no active streak): streak breaks.
    if [ "$_ds" -gt 0 ]; then
      # Save this streak's earned credits so the next streak can inherit them.
      _prev_streak_credits=$_cur_streak_credits
      _cur_streak_credits=0
    fi
    _ds=0
    _rs=0
    _bank=0
  fi
}

# compute_streaks <rows_file> <as_of_date YYYY-MM-DD>
# Walks the whole log forward in Python (no per-day subprocess forks) and
# echoes "<day_streak> <row_streak> <bank> <cur_streak_credits>".
compute_streaks() {
  python3 - "$1" "$2" <<'PYEOF'
import sys
from datetime import date, timedelta

rows_file, as_of = sys.argv[1], date.fromisoformat(sys.argv[2])

days = {}
with open(rows_file) as f:
    for line in f:
        s = line.strip()
        if s and s[0].isdigit() and len(s) >= 10:
            try:
                d = date.fromisoformat(s[:10])
                days[d] = days.get(d, 0) + 1
            except ValueError:
                pass

ds = rs = bank = prev_cred = cur_cred = 0
cur_year = None

def year_reset(y):
    global ds, rs, bank, prev_cred, cur_cred, cur_year
    if cur_year is not None and y != cur_year:
        ds = rs = bank = prev_cred = cur_cred = 0
    cur_year = y

def step(count):
    global ds, rs, bank, prev_cred, cur_cred
    if count > 0:
        if ds == 0:
            ds = 1; rs = count
            bank = prev_cred + count - 1
            cur_cred = count - 1; prev_cred = 0
        else:
            ds += 1; rs += count
            bank += count - 1; cur_cred += count - 1
    elif ds > 0 and bank > 0:
        bank -= 1; ds += 1
    else:
        if ds > 0:
            prev_cred = cur_cred; cur_cred = 0
        ds = rs = bank = 0

prev_day = None
for d, count in sorted(days.items()):
    if prev_day is not None:
        for i in range(1, (d - prev_day).days):
            gd = prev_day + timedelta(days=i)
            year_reset(gd.year); step(0)
    year_reset(d.year); step(count)
    prev_day = d

if prev_day is not None:
    for i in range(1, (as_of - prev_day).days):
        gd = prev_day + timedelta(days=i)
        year_reset(gd.year); step(0)

print(ds, rs, bank, cur_cred)
PYEOF
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
  read -r DAY_STREAK COUNT_STREAK _ _ < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

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

# Fetch upstream changes and rebase local commits onto origin/main before any
# commit, so a row logged on another machine doesn't cause a push rejection.
# Called with a clean working tree; aborts a failed rebase and stops loudly
# rather than leaving the repo mid-rebase.
sync_with_origin() {
  git -C "$SCRIPT_DIR" fetch origin
  if ! git -C "$SCRIPT_DIR" rebase origin/main; then
    git -C "$SCRIPT_DIR" rebase --abort 2>/dev/null || true
    echo "ERROR: rebase onto origin/main failed — resolve manually before logging" >&2
    exit 1
  fi
}

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
  # Sync with origin first (clean tree here), so the last local commit we're
  # about to rewrite is on top of the latest origin/main.
  sync_with_origin
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
  # Sync with origin before committing (clean tree here).
  sync_with_origin
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

# Current streaks — computed before the 2-week display so the active-streak
# annotation on the final line can show the global (year-to-date) numbers.
read -r DAY_STREAK COUNT_STREAK _ _ < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

# Recent activity — last 14 calendar days
echo ""
echo "--- Last 2 Weeks ---"
# Calculate running total (year_rows - day_of_year) for the day before the window
first_day=$(date -j -v-13d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
first_doy=$(date -j -f "%Y-%m-%d" "$first_day" "+%-j")
rows_up_to_before=$(awk -v d="$first_day" -v y="$YEAR" '$0 ~ "^"y"-" && $0 < d"T"' "$ROWS_FILE" | wc -l | tr -d ' ')
running_total=$((rows_up_to_before - (first_doy - 1)))

# Initialise the 2-week window's streak state from the global streak position
# entering the first day of the window, so covered-rest-day bank numbers are
# accurate rather than being based on a local-window approximation from zero.
read -r _wini_ds _wini_rs _wini_bank _wini_cur < <(compute_streaks "$ROWS_FILE" "$first_day")

# Streak state for the window walks through the same _streak_step rule as the
# headline number, so a covered rest day is treated identically in both.
buffered_line=""
_ds=$_wini_ds
_rs=$_wini_rs
_bank=$_wini_bank
_prev_streak_credits=0
_cur_streak_credits=$_wini_cur
best_day_streak=0
best_row_streak=0
_2wk_year=""
for i in $(seq 13 -1 0); do
  day=$(date -j -v-${i}d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
  # Year boundary: streaks cannot cross 12/31 → 01/01.
  if [ -n "$_2wk_year" ] && [ "${day:0:4}" != "$_2wk_year" ]; then
    if [ -n "$buffered_line" ]; then echo "$buffered_line"; buffered_line=""; fi
    _ds=0; _rs=0; _bank=0; _prev_streak_credits=0; _cur_streak_credits=0
  fi
  _2wk_year="${day:0:4}"
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
    RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
    printf "%s %s %s-%s~%s   %3d  (rest — streak held, bank %d)\n" "$dow" "$day" "$RED" "$YEL" "$RST" "$running_total" "$_bank"
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
  if [ "$DAY_STREAK" -gt 0 ]; then
    GRN=$'\033[32m'; RST=$'\033[0m'
    printf "%s  %s🔥 %dd %dr streak%s\n" "$buffered_line" "$GRN" "$DAY_STREAK" "$COUNT_STREAK" "$RST"
  else
    echo "$buffered_line"
  fi
fi

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
