#!/usr/bin/env bash
# Tests for the rest-day bank streak rule in row.sh.
#
# Each case builds a fixture rows.txt in a throwaway temp dir alongside a copy
# of row.sh, runs `row.sh --dry <as_of>` (which never writes, commits, or posts),
# and asserts the headline "Day streak: D | Row streak: R" line.
#
# The live rows.txt is never modified — case 6 copies it read-only into a fixture.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROW_SH="$REPO_DIR/row.sh"
REAL_ROWS="$REPO_DIR/rows.txt"

PASS=0
FAIL=0

# run_streak <as_of_timestamp> <rows_file_contents...via stdin>
# Echoes "D R" parsed from the "Day streak: D | Row streak: R" output line.
run_case_output() {
  local as_of="$1" rows_content="$2"
  local tmp
  tmp="$(mktemp -d)"
  cp "$ROW_SH" "$tmp/row.sh"
  printf '%s' "$rows_content" > "$tmp/rows.txt"
  local out
  out="$(cd "$tmp" && bash ./row.sh --dry "$as_of" 2>&1)"
  rm -rf "$tmp"
  printf '%s' "$out"
}

streak_pair() {
  # Extract "D R" from a full run's output.
  grep -E '^Day streak:' <<<"$1" | sed -E 's/^Day streak:[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*Row streak:[[:space:]]*([0-9]+).*/\1 \2/'
}

assert_streak() {
  local name="$1" as_of="$2" rows_content="$3" want_day="$4" want_row="$5"
  local out pair got_day got_row
  out="$(run_case_output "$as_of" "$rows_content")"
  pair="$(streak_pair "$out")"
  got_day="${pair% *}"
  got_row="${pair#* }"
  if [ "$got_day" = "$want_day" ] && [ "$got_row" = "$want_row" ]; then
    echo "ok   - $name (day=$got_day row=$got_row)"
    PASS=$((PASS + 1))
  else
    echo "FAIL - $name: want day=$want_day row=$want_row, got day=$got_day row=$got_row"
    FAIL=$((FAIL + 1))
  fi
}

# Assert day/row streak are at least the given lower bounds (used for the real log).
assert_streak_atleast() {
  local name="$1" as_of="$2" rows_content="$3" min_day="$4" min_row="$5"
  local out pair got_day got_row
  out="$(run_case_output "$as_of" "$rows_content")"
  pair="$(streak_pair "$out")"
  got_day="${pair% *}"
  got_row="${pair#* }"
  if [ "$got_day" -ge "$min_day" ] && [ "$got_row" -ge "$min_row" ]; then
    echo "ok   - $name (day=$got_day row=$got_row, >= ${min_day}/${min_row})"
    PASS=$((PASS + 1))
  else
    echo "FAIL - $name: want day>=$min_day row>=$min_row, got day=$got_day row=$got_row"
    FAIL=$((FAIL + 1))
  fi
}

NL=$'\n'   # command substitution strips trailing newlines, so join explicitly.

# ── Case 1: a miss WITH credits available — the streak survives ───────────────
# 03-01 has 2 rows (banks 1 credit); 03-03 is missed but covered. Covered days
# DO count toward the day streak (01,02,03=covered,04 = 4 streak days) and do
# not change the row streak (2+1+1 = 4).
C1="2026-03-01T08:00:00-07:00${NL}2026-03-01T18:00:00-07:00${NL}2026-03-02T08:00:00-07:00${NL}2026-03-04T08:00:00-07:00${NL}"
assert_streak "case1: miss with credit survives" "2026-03-04T08:00:00-07:00" "$C1" 4 4

# ── Case 2: a miss with an EMPTY bank — the streak breaks ─────────────────────
# 03-01 one row (no credit), 03-02 missed with empty bank -> break. Only 03-03
# remains in the current streak.
C2="2026-03-01T08:00:00-07:00${NL}2026-03-03T08:00:00-07:00${NL}"
assert_streak "case2: miss with empty bank breaks" "2026-03-03T08:00:00-07:00" "$C2" 1 1

# ── Case 3: two misses in a row with only ONE credit — breaks on the second ───
# 03-01 two rows (1 credit). 03-02 covered (bank->0). 03-03 missed, empty bank
# -> break. Current streak is just 03-04.
C3="2026-03-01T08:00:00-07:00${NL}2026-03-01T18:00:00-07:00${NL}2026-03-04T08:00:00-07:00${NL}"
assert_streak "case3: two misses, one credit -> breaks on 2nd" "2026-03-04T08:00:00-07:00" "$C3" 1 1

# ── Case 4: the balance never goes negative ──────────────────────────────────
# One credit then THREE consecutive misses. Credit covers the first miss; the
# bank floors at 0 (never negative), so the 2nd miss breaks. The current streak
# is only the post-break 03-06 row — proving the extra misses could not push the
# balance below zero and keep the streak "alive".
C4="2026-03-01T08:00:00-07:00${NL}2026-03-01T18:00:00-07:00${NL}2026-03-06T08:00:00-07:00${NL}"
assert_streak "case4: balance floored at zero" "2026-03-06T08:00:00-07:00" "$C4" 1 1

# ── Case 5: credits from a broken streak carry into the next one ──────────────
# 03-01 has 3 rows (2 credits). 03-02, 03-03 covered (bank->0), 03-04 missed ->
# break. The 2 credits earned on 03-01 are INHERITED by the new streak starting
# on 03-05, so 03-06 is covered (bank->1) and the streak extends to 03-07.
C5="2026-03-01T06:00:00-07:00${NL}2026-03-01T12:00:00-07:00${NL}2026-03-01T18:00:00-07:00${NL}2026-03-05T08:00:00-07:00${NL}2026-03-07T08:00:00-07:00${NL}"
assert_streak "case5: prev streak credits carry into next streak" "2026-03-07T08:00:00-07:00" "$C5" 3 2

# ── Case 6: the captain's real 2026-08-10 -> 2026-08-14 sequence is unbroken ──
# Self-contained tail: 08-10 (2 rows, banks 1), 08-11, 08-12, 08-13 missed
# (covered by the 08-10 credit), 08-14. Five streak days (covered 08-13 counts),
# five rows, unbroken.
C6="2026-08-10T12:24:20-07:00${NL}2026-08-10T14:27:37-07:00${NL}2026-08-11T14:03:00-07:00${NL}2026-08-12T13:59:09-07:00${NL}2026-08-14T10:32:51-07:00${NL}"
assert_streak "case6: captain 08-10->08-14 unbroken" "2026-08-14T10:32:51-07:00" "$C6" 5 5

# ── Case 6b: against a read-only copy of the REAL rows.txt ───────────────────
# The real log must yield an unbroken streak across the missed 2026-08-13. Under
# the OLD reset-on-miss rule the current streak would be just 08-14 (1 day); the
# bank rule bridges 08-09 and 08-13, so the streak reaches well past them.
if [ -f "$REAL_ROWS" ]; then
  REAL_CONTENT="$(cat "$REAL_ROWS")"
  assert_streak_atleast "case6b: real rows.txt bridges 08-13" "2026-08-14T10:32:51-07:00" "$REAL_CONTENT" 5 6
else
  echo "skip - case6b: real rows.txt not found"
fi

echo ""
echo "streak tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
