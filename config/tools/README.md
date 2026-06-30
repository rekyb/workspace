# tools/ — tool dependencies

Each `ensure-<name>.sh` is an **idempotent** installer for one CLI tool that
isn't a git repo (so it doesn't belong in `manifest`). `bootstrap.sh` runs every
`ensure-*.sh` here, sorted, after cloning the repos in `manifest`.

Contract for an `ensure-*.sh`:

- POSIX `sh`-safe, `$HOME`-relative (no hardcoded usernames/paths beyond `$HOME`).
- Skip work that's already done — check before installing/configuring.
- Exit `0` on success, non-zero on a real failure. A non-zero exit makes
  bootstrap print a ⚠ and count the tool as failed, but does **not** abort the
  run (repo hydration stays the priority).
- Announce any change outside the meta-repo (e.g. edits to the global
  `~/.claude/settings.json`) before making it.

To add a tool: drop in `ensure-<name>.sh`, `chmod +x` it, and re-run
`./bootstrap.sh`.

## Current tools

- **`ensure-rtk.sh`** — installs [RTK](https://github.com/rtk-ai/rtk) (Rust Token
  Killer) via its curl script if `rtk` is missing, then runs `rtk init -g` to
  register the Claude Code PreToolUse hook (unless already registered). `rtk init
  -g` modifies the global `~/.claude/settings.json`; restart Claude Code afterward.
