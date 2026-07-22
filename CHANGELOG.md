# row_tracker — Changelog

## 2026-07-21 — row pomodoro subcommand (task-nmc9, Part B)

Files: row.sh, CHANGELOG.md

Added a `pomodoro` subcommand to `row.sh` via a reserved-word dispatch at the
top of the script — `$1` is still treated as a row timestamp for every other
invocation, so the existing log-a-row / rows.txt / git-commit flow is unchanged.

`row pomodoro` READS the Talon Pomodoro timer's wall-clock state from
`~/.talon/pomodoro-state.json` (written by the Talon side, `pomodoro.py` —
Part A, Edgar) and prints the end time + remaining. It does not build a timer
and never writes the state file. Shared contract:
`{"active": bool, "end_iso": "...", "end_epoch": N, "paused": bool}`.

- Active → `🍅 Pomodoro active — ends <end_iso> (Nm SSs remaining)`
- Paused → `⏸️ Pomodoro paused — ends <end_iso> (... remaining when resumed)`
- Ended (epoch passed) → shows how long ago it ended
- No state file / `active:false` → friendly "No active pomodoro" message

Verified: all state branches render correctly against fixture files; existing
row-logging preserved (`--dry`, bare preview, and bad-timestamp rejection).

## 2026-07-04 — session 2bd84405

Files: row.sh
## 2026-06-14 — session a699f078

Files: row.sh

> AI summary pending — check ProjectDocs Handover in next session.
## 2026-05-22 — session 653b0c8f

Files: row.sh

> AI summary pending — check ProjectDocs Handover in next session.
## 2026-05-19 — session d1c76179

Files: rows.txt

> AI summary pending — check ProjectDocs Handover in next session.
## 2026-05-14 — session 6a4f9553

Files: row.sh

> AI summary pending — check ProjectDocs Handover in next session.
