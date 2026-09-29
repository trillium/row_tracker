# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
- Streak logic lives entirely in `row.sh` (not `src/`). The rest-day bank rule
  (`bank == rows - days`, no inheritance) is documented at the top of `row.sh`;
  every log walk (live stats, `post-slack`, 2-week view, `row year`) routes each
  calendar day through the single `_streak_step` function so they can never
  disagree. Never edit `rows.txt` — it is the real training log; copy it into
  fixtures instead.
- `row.sh` layout: §0 paths/colors (once) → §1 streak core (`_streak_step`,
  `compute_streaks`, must stay in sync) → §2 helpers (date/count, `mark_field`,
  `year_pace`, `slack_text`/`slack_post`) → §5 `cmd_*` subcommands →
  §6 dispatch → §7 main log flow. Call `row --help` for subcommands.
- Bash tests for the streak rule: `npm run test:sh` (runs `tests/streak_test.sh`).
  Jest (`npm test`) covers the `src/` web view only.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
