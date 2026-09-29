#!/usr/bin/env bash
set -euo pipefail

# ~~ 0. Repo paths & shared constants (resolved once) ~~
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROWS_FILE="$SCRIPT_DIR/rows.txt"
SLACK_CREDS="$SCRIPT_DIR/.slack-creds"
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'

# ── Streak computation: the rest-day bank rule ───────────────────────────────
# Extra effort earlier in a streak buys forgiveness for a single missed day.
#
#   * Every row beyond the first on one calendar day deposits ONE credit
#     (two rows in a day = 1 credit, three rows = 2 credits, ...).
#   * A calendar day with zero rows WITHDRAWS one credit and the streak carries
#     through that day unbroken (a "covered" rest day).
#   * The balance may never go negative: an empty bank plus a missed day breaks
#     the streak exactly as it always did. There is no cap on the balance.
#   * When a streak breaks, the next row starts fresh at 1 day (no inheritance).
#   * A covered rest day keeps the streak ALIVE: it DOES count toward the day
#     streak (calendar days) but does NOT change the row streak, so the bank
#     drops by exactly 1.
#
# Invariant (no inheritance): _bank == _rs - _ds whenever _ds > 0.
#   3 days 5 rows -> bank 2 | 3 days 3 rows -> bank 0 | rows < days -> broken.
#
# _streak_step applies one calendar day to the running state held in the globals
# _ds (day streak), _rs (row streak), _bank (rest-day balance).
# Every place that walks the log — the live views and the
# 2-week history — routes each day through this one function.
_streak_step() {
  local count="$1"
  if [ "$count" -gt 0 ]; then
    if [ "$_ds" -eq 0 ]; then
      # Fresh start after a break (no inheritance): 1 day, N rows.
      _ds=1
      _rs="$count"
      _bank=$((count - 1))
    else
      _ds=$(($_ds + 1))
      _rs=$(($_rs + count))
      _bank=$(($_bank + count - 1))
    fi
  elif [ "$_ds" -gt 0 ] && [ "$_bank" -gt 0 ]; then
    # Covered rest day: spend one credit, streak holds. Day streak grows
    # (calendar days), row streak unchanged, so bank drops by exactly 1.
    _bank=$(($_bank - 1))
    _ds=$(($_ds + 1))
  else
    # Empty bank (or no active streak): streak breaks, no inheritance.
    _ds=0
    _rs=0
    _bank=0
  fi
}

# compute_streaks <rows_file> <as_of_date YYYY-MM-DD>
# Walks the whole log forward in Python (no per-day subprocess forks) and
# echoes "<day_streak> <row_streak> <bank>".
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

ds = rs = bank = 0
cur_year = None

def year_reset(y):
    global ds, rs, bank, cur_year
    if cur_year is not None and y != cur_year:
        ds = rs = bank = 0
    cur_year = y

def step(count):
    global ds, rs, bank
    if count > 0:
        if ds == 0:
            ds = 1; rs = count
            bank = count - 1
        else:
            ds += 1; rs += count
            bank += count - 1
    elif ds > 0 and bank > 0:
        bank -= 1; ds += 1
    else:
        ds = rs = bank = 0

# Only days on or before as_of count — future rows are ignored.
past = sorted((d, c) for d, c in days.items() if d <= as_of)
prev_day = None
for d, count in past:
    if prev_day is not None:
        for i in range(1, (d - prev_day).days):
            gd = prev_day + timedelta(days=i)
            year_reset(gd.year); step(0)
    year_reset(d.year); step(count)
    prev_day = d

if prev_day is not None:
    # Step every gap day through as_of inclusive. If as_of itself has no
    # rows it counts as a miss/cover/break; if it does, it was just stepped.
    for i in range(1, (as_of - prev_day).days + 1):
        gd = prev_day + timedelta(days=i)
        year_reset(gd.year); step(0)

print(ds, rs, bank)
PYEOF
}

# ~~ 2. Shared helpers ~~
# Date helpers wrap macOS `date -j`; count helpers read ROWS_FILE.

dow_of() { date -j -f "%Y-%m-%d" "$1" "+%a"; }
doy_of() { date -j -f "%Y-%m-%d" "$1" "+%-j"; }
count_for_day() { grep -c "^${1}T" "$ROWS_FILE" || true; }
rows_for_year() { grep -c "^${1}-" "$ROWS_FILE" || true; }
days_in_year() {
  local y="$1"
  if (( y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) )); then echo 366; else echo 365; fi
}
shift_day() { date -j -v"${2}" -f "%Y-%m-%d" "$1" "+%Y-%m-%d"; }

reset_streak_state() { _ds=0; _rs=0; _bank=0; }

# mark_field <plain> <colored> [width] — echoes the colored marker padded with
# spaces to a fixed visual width (escape codes are zero-width, so pad from the
# plain-text length). Keeps day-list columns aligned.
mark_field() {
  local plain="$1" colored="$2" width="${3:-6}"
  local pad=$((width - ${#plain}))
  if [ "$pad" -lt 1 ]; then pad=1; fi
  printf '%s%*s' "$colored" "$pad" ""
}

# year_pace <timestamp> <row_num> — sets DAY_OF_YEAR DIFF DAYS_IN_YEAR
# PCT_THROUGH DAYS_LEFT ROW_NUM YEAR globals from a timestamp + row count.
year_pace() {
  local ts="$1" n="$2"
  YEAR="${ts:0:4}"
  DAY_OF_YEAR=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${ts:0:19}" "+%-j" 2>/dev/null || date -j -f "%Y-%m-%dT%T" "${ts:0:19}" "+%-j")
  DAYS_IN_YEAR=$(days_in_year "$YEAR")
  DAYS_LEFT=$((DAYS_IN_YEAR - DAY_OF_YEAR))
  PCT_THROUGH=$((DAY_OF_YEAR * 100 / DAYS_IN_YEAR))
  ROW_NUM="$n"
  DIFF=$((ROW_NUM - DAY_OF_YEAR))
}

# slack_text — echoes the one-line summary from ROW_NUM, DAYS_IN_YEAR,
# DAY_OF_YEAR, PCT_THROUGH, DIFF, DAY_STREAK, COUNT_STREAK.
slack_text() {
  local pace streak=""
  if [ "$DIFF" -gt 0 ]; then pace="📈 ${DIFF} ahead"
  elif [ "$DIFF" -lt 0 ]; then pace="📉 $((-DIFF)) behind"
  else pace="📊 on pace"; fi
  if [ "${COUNT_STREAK:-0}" -gt 0 ]; then streak=" · 🔥 ${DAY_STREAK}day ${COUNT_STREAK}row streak"; fi
  echo "🚣 Row ${ROW_NUM}/${DAYS_IN_YEAR} · 📅 Day ${DAY_OF_YEAR}/${DAYS_IN_YEAR} (${PCT_THROUGH}%) · ${pace}${streak}"
}

# slack_post <msg> — posts via creds file; prints ok/fail receipt.
slack_post() {
  set -a; . "$SLACK_CREDS"; set +a
  local resp
  resp=$(curl -s --max-time 5 -X POST "${SLACK_API_BASE}/chat.postMessage" \
    -H "Cookie: $SLACK_COOKIE" \
    --data-urlencode "token=$SLACK_TOKEN" \
    --data-urlencode "channel=$SLACK_CHANNEL" \
    --data-urlencode "text=$1" 2>&1) || resp="curl_error"
  if echo "$resp" | grep -q '"ok":true'; then
    echo "✓ posted to #${SLACK_CHANNEL_NAME}"
  else
    echo "✗ slack post failed: $(echo "$resp" | head -c 200)"
  fi
}

# ~~ 5. Subcommands (one cmd_* function each) ~~
# row.sh treats $1 as a timestamp by default. Reserved words branch first;
# anything else falls through to the main log flow below.

# `row pomodoro` reads the Talon Pomodoro timer's wall-clock state and prints
# the end time + remaining. The state file is owned/written by the Talon side
# (pomodoro.py) per the shared contract; row only READS it.
#   File:  ~/.talon/pomodoro-state.json
#   Shape: {"active": bool, "end_iso": "...", "end_epoch": N, "paused": bool}
cmd_pomodoro() {
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
}
# ─────────────────────────────────────────────────────────────────────────────

# `row post-slack` posts the stats for the LAST already-logged row to Slack
# again, without appending a timestamp or making a git commit. Useful when a
# post failed or you want a re-post of the current standing.
cmd_post_slack() {
  shift
  TIMESTAMP=$(grep "^[0-9]" "$ROWS_FILE" | tail -1)
  if [ -z "$TIMESTAMP" ]; then
    echo "ERROR: no rows logged yet in $ROWS_FILE" >&2
    exit 1
  fi
  YEAR="${TIMESTAMP:0:4}"

  # ROW_NUM is the count itself here (not COUNT+1) — TIMESTAMP is already
  # the last logged row, so it IS row number COUNT, not the next one.
  year_pace "$TIMESTAMP" "$(rows_for_year "$YEAR")"

  # Current streaks (day + row) under the rest-day bank rule. TIMESTAMP here is
  # the last logged row, so its date is the as-of day.
  read -r DAY_STREAK COUNT_STREAK BANK < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

  echo "--- Row Stats (last logged row — no new entry made) ---"
  echo "Row #${ROW_NUM} of ${YEAR}"
  echo "Day #${DAY_OF_YEAR} of ${DAYS_IN_YEAR} (${PCT_THROUGH}% through ${YEAR})"
  echo "Day streak: ${DAY_STREAK} | Row streak: ${COUNT_STREAK}"

  MSG=$(slack_text)

  echo ""
  echo "--- Slack post ---"
  echo "→ $MSG"

  if [ ! -f "$SLACK_CREDS" ]; then
    echo "ERROR: $SLACK_CREDS not found — cannot post to Slack" >&2
    exit 1
  fi
  slack_post "$MSG"
  exit 0
}
# ─────────────────────────────────────────────────────────────────────────────

# `row path` prints the absolute path to the row_tracker code dir (the dir
# containing this script / rows.txt). Useful for scripts / agents that need
# to locate the repo without hardcoding $HOME paths.
cmd_path() {
  echo "$SCRIPT_DIR"
  exit 0
}
# ─────────────────────────────────────────────────────────────────────────────

# `row year [YYYY]` prints every day of the year with its streak state and a
# streak summary (each streak + the day it ended). Bank invariant always holds:
# bank == rows - days for the active streak. Defaults to the current year.
# For the current year the walk stops at today; for a past year it walks the
# full Jan 01 → Dec 31.
cmd_year() {
  shift
  TODAY_YEAR=$(date "+%Y")
  TODAY_DAY=$(date "+%Y-%m-%d")
  if [ -n "${1:-}" ]; then
    YEAR_ARG="$1"
    if ! [[ "$YEAR_ARG" =~ ^[0-9]{4}$ ]]; then
      echo "ERROR: invalid year: $YEAR_ARG (expected YYYY, e.g. 2026)" >&2
      exit 1
    fi
  else
    YEAR_ARG="$TODAY_YEAR"
  fi
  if [ "$YEAR_ARG" = "$TODAY_YEAR" ]; then
    END_DAY="$TODAY_DAY"
  else
    END_DAY="${YEAR_ARG}-12-31"
  fi
  START_DAY="${YEAR_ARG}-01-01"
  if [ ! -f "$ROWS_FILE" ]; then
    echo "ERROR: $ROWS_FILE not found" >&2
    exit 1
  fi

  reset_streak_state
  streak_start=""
  streaks=""
  n_streaks=0
  best_ds=0; best_rs=0
  rows_so_far=0
  day="$START_DAY"
  echo ""
  echo "--- $YEAR_ARG full year ($START_DAY → $END_DAY) ---"
  while [ "$day" \< "$END_DAY" ] || [ "$day" = "$END_DAY" ]; do
    dow=$(dow_of "$day")
    doy=$(doy_of "$day")
    count=$(count_for_day "$day")
    rows_so_far=$((rows_so_far + count))
    pace=$((rows_so_far - doy))
    prev_ds=$_ds; prev_rs=$_rs
    if [ "$count" -gt 0 ] && [ "$_ds" -eq 0 ]; then
      streak_start="$day"
    fi
    _streak_step "$count"
    if [ "$count" -gt 0 ]; then
      pluses=$(printf '+%.0s' $(seq 1 $count))
      field=$(mark_field "-${pluses}" "${RED}-${GRN}${pluses}${RST}")
      printf "%-3s %s %s pace %+4d  [%3dd %3dr, bank %3d]\n" "$dow" "$day" "$field" "$pace" "$_ds" "$_rs" "$_bank"
    elif [ "$prev_ds" -gt 0 ] && [ "$_ds" -gt 0 ]; then
      field=$(mark_field "-~" "${RED}-${YEL}~${RST}")
      printf "%-3s %s %s pace %+4d  [%3dd %3dr, bank %3d]  (rest — streak held)\n" "$dow" "$day" "$field" "$pace" "$_ds" "$_rs" "$_bank"
    else
      RED=$'\033[31m'; RST=$'\033[0m'
      if [ "$prev_ds" -gt 0 ]; then
        # Streak ended this day: record start → yesterday with its final totals.
        end_day=$(shift_day "$day" -1d)
        n_streaks=$((n_streaks + 1))
        printf -v entry "%2d. %s → %s: %3dd %3dr (ended %s)" "$n_streaks" "$streak_start" "$end_day" "$prev_ds" "$prev_rs" "$day"
        streaks="${streaks}${entry}\n"
        if [ "$prev_ds" -gt "$best_ds" ]; then best_ds=$prev_ds; fi
        if [ "$prev_rs" -gt "$best_rs" ]; then best_rs=$prev_rs; fi
        field=$(mark_field "-x" "${RED}-x${RST}")
        printf "%-3s %s %s pace %+4d  [%3dd %3dr, bank   0]  (miss — streak ended)\n" "$dow" "$day" "$field" "$pace" "$prev_ds" "$prev_rs"
        streak_start=""
      else
        field=$(mark_field "-" "${RED}-${RST}")
        printf "%-3s %s %s pace %+4d\n" "$dow" "$day" "$field" "$pace"
      fi
    fi
    if [ "$day" = "$END_DAY" ]; then break; fi
    day=$(shift_day "$day" +1d)
  done
  echo ""
  echo "--- Streaks ($YEAR_ARG) ---"
  if [ -n "$streaks" ]; then
    printf "%b" "$streaks"
  fi
  if [ "$_ds" -gt 0 ]; then
    n_streaks=$((n_streaks + 1))
    printf "%2d. %s → %s: %3dd %3dr (active, bank %3d)\n" "$n_streaks" "$streak_start" "$END_DAY" "$_ds" "$_rs" "$_bank"
  elif [ -z "$streaks" ]; then
    echo "(no streaks)"
  fi
  if [ "$_ds" -gt "$best_ds" ]; then best_ds=$_ds; fi
  if [ "$_rs" -gt "$best_rs" ]; then best_rs=$best_rs; fi
  if [ "$best_ds" -gt 0 ]; then
    printf "Best: ${GRN}%3dd %3dr${RST} | Current: %3dd %3dr (bank %3d)\n" "$best_ds" "$best_rs" "$_ds" "$_rs" "$_bank"
  fi
  exit 0
}
# ─────────────────────────────────────────────────────────────────────────────

# cmd_last — print the most recent logged timestamp (bare `row` / `row last`).
cmd_last() {
  local last=""
  # Last NON-EMPTY line: the log may end in blank lines, and early history is
  # unknown (`??`) — neither is a timestamp.
  [ -f "$ROWS_FILE" ] && last=$(awk 'NF {last=$0} END {printf "%s", last}' "$ROWS_FILE")
  if [ -z "$last" ]; then
    echo "no rows logged yet" >&2
    exit 1
  fi
  echo "$last"
  exit 0
}

# ~~ 6. Subcommand dispatch (thin; bodies live in cmd_* above) ~~
case "${1:-}" in
  pomodoro) cmd_pomodoro "$@" ;;
  post-slack) cmd_post_slack "$@" ;;
  path) cmd_path "$@" ;;
  year) cmd_year "$@" ;;
  last) cmd_last ;;
esac

# ~~ 7. Main flow: parse args, validate, log, report ~~
DRY_RUN=false
REPLACE=false
print_help() {
  cat << 'EOF'
row — rowing tracker with Slack integration

USAGE:
  row                          # Print the last logged row timestamp
  row [OPTIONS] [TIMESTAMP]
  row SUBCOMMAND

OPTIONS:
  --help, -h         Show this help message
  --dry              Show stats without logging
  --replace          Replace last logged entry with new timestamp

TIMESTAMP FORMAT:
  YYYY-MM-DDTHH:MM:SS±HH:MM  (ISO 8601 with timezone)
  Example: 2026-06-06T08:22:31-07:00

SUBCOMMANDS:
  pomodoro           Show current Pomodoro timer state
  post-slack         Post last row's stats to Slack without logging
  last               Print the last logged row timestamp
  path               Output the path of the code dir
  year [YYYY]        Full-year day list plus each streak and its end day

EXAMPLES:
  row                              # Print the last logged row timestamp
  row --dry                        # Dry run with current time
  row 2026-07-26T19:20:05-07:00   # Log a row for specific timestamp
  row now                          # Log current time
  row --replace 2026-07-26T19:20:05-07:00  # Replace last entry
  row --dry                        # Dry run (same as no args)
  row pomodoro                     # Show Pomodoro state
  row post-slack                   # Post to Slack
  row path                         # Output the path of the code dir
  row year                         # Full current year with streaks
  row year 2026                    # Full 2026 with streaks
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  print_help
  exit 0
elif [ "${1:-}" = "--dry" ]; then
  DRY_RUN=true
  shift
elif [ "${1:-}" = "--replace" ]; then
  REPLACE=true
  shift
fi

# Bare `row` (no flags, no args) prints the last logged timestamp; `--dry`
# keeps the classic dry-stats run with the current time.
if [ -z "${1:-}" ] && [ "$DRY_RUN" = false ]; then
  cmd_last
elif [ -z "${1:-}" ]; then
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

# Stats for the newly logged (or dry-run) timestamp.
year_pace "$TIMESTAMP" "$((COUNT + 1))"

# Current streaks — computed before the 2-week display so the active-streak
# annotation on the final line can show the global (year-to-date) numbers.
read -r DAY_STREAK COUNT_STREAK BANK < <(compute_streaks "$ROWS_FILE" "${TIMESTAMP:0:10}")

# Recent activity — last 14 calendar days
echo ""
echo "--- Last 2 Weeks ---"
# Calculate running total (year_rows - day_of_year) for the day before the window
first_day=$(date -j -v-13d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
first_doy=$(date -j -f "%Y-%m-%d" "$first_day" "+%-j")
rows_up_to_before=$(awk -v d="$first_day" -v y="$YEAR" '$0 ~ "^"y"-" && $0 < d"T"' "$ROWS_FILE" | wc -l | tr -d ' ')
running_total=$((rows_up_to_before - (first_doy - 1)))

# Initialise the 2-week window's streak state from the global streak position
# as of the day BEFORE the window, so the first window day is stepped exactly
# once below (compute_streaks includes its as_of day). This keeps bank numbers
# accurate rather than using a local-window approximation from zero.
_wini_day=$(shift_day "$first_day" -1d)
read -r _wini_ds _wini_rs _wini_bank < <(compute_streaks "$ROWS_FILE" "$_wini_day")

# Streak state for the window walks through the same _streak_step rule as the
# headline number, so a covered rest day is treated identically in both.
buffered_line=""
_ds=$_wini_ds
_rs=$_wini_rs
_bank=$_wini_bank
best_day_streak=0
best_row_streak=0
_2wk_year=""
for i in $(seq 13 -1 0); do
  day=$(date -j -v-${i}d -f "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP:0:19}" "+%Y-%m-%d")
  # Year boundary: streaks cannot cross 12/31 → 01/01.
  if [ -n "$_2wk_year" ] && [ "${day:0:4}" != "$_2wk_year" ]; then
    if [ -n "$buffered_line" ]; then echo "$buffered_line"; buffered_line=""; fi
    _ds=0; _rs=0; _bank=0
  fi
  _2wk_year="${day:0:4}"
  dow=$(dow_of "$day")
  count=$(count_for_day "$day")
  running_total=$((running_total + count - 1))
  if [ "$count" -gt 0 ]; then
    # Print any buffered line first
    if [ -n "$buffered_line" ]; then
      echo "$buffered_line"
    fi
    _streak_step "$count"
    pluses=$(printf '+%.0s' $(seq 1 $count))
    field=$(mark_field "-${pluses}" "${RED}-${GRN}${pluses}${RST}" 5)
    buffered_line=$(printf "%s %s %s%3d" "$dow" "$day" "$field" "$running_total")
  elif [ "$_ds" -gt 0 ] && [ "$_bank" -gt 0 ]; then
    # Covered rest day: spend a credit, the streak holds through unbroken. Flush
    # the buffered rowing line first so the rest day prints after it, then keep
    # the streak alive (day streak grows, row streak unchanged, bank -1).
    if [ -n "$buffered_line" ]; then
      echo "$buffered_line"
      buffered_line=""
    fi
    _streak_step 0
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
    printf "%s %s %s-%s    %3d\n" "$dow" "$day" "$RED" "$RST" "$running_total"
  fi
done
# Flush any remaining buffered line (active streak, no ending yet)
if [ -n "$buffered_line" ]; then
  if [ "$_ds" -gt 0 ]; then
    printf "%s  %s🔥 %dd %dr streak%s\n" "$buffered_line" "$GRN" "$_ds" "$_rs" "$RST"
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
if [ "$DRY_RUN" = false ] && [ "$REPLACE" = false ] && [ -f "$SLACK_CREDS" ]; then
  MSG=$(slack_text)

  echo ""
  echo "--- Slack post ---"
  echo "→ $MSG"
  slack_post "$MSG"
fi
