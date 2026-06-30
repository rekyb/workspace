# RTK Integration — Design Spec

**Date:** 2026-06-30
**Status:** Approved

## Goal

Make [RTK](https://github.com/rtk-ai/rtk) (Rust Token Killer — a CLI proxy that
compresses command output to cut LLM token use) part of the workspace meta-repo
so that on a fresh device, a single `./bootstrap.sh` installs the `rtk` binary if
missing and wires its Claude Code hook automatically — no manual reconfiguration.

## Background

RTK is a single Rust binary (zero runtime deps). It integrates with Claude Code
via a **PreToolUse hook**: `rtk init -g` installs `rtk-rewrite.sh` (transparently
rewrites e.g. `git status` → `rtk git status`), writes an `RTK.md` context file,
and registers the hook in the **global** `~/.claude/settings.json`. A Claude Code
restart is required for the hook to activate.

RTK is a *tool dependency*, not a git repo — so it does not belong in `manifest`
(which clones repos into the tree). It is handled by a new tracked `config/tools/`
mechanism.

## Decisions

- **Scope:** Binary install **and** auto-wire the hook (`rtk init -g`).
- **Install method:** the curl install script
  (`curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`),
  which installs to `~/.local/bin`. Most portable — works on Linux and macOS with
  no Rust toolchain or Homebrew prerequisite.
- **Global side-effects are announced, never silent.** `rtk init -g` modifies the
  user's global `~/.claude/settings.json`; bootstrap prints a clear notice before
  doing so. (Honors the prior global-config incident lesson.)

## Architecture

### `config/tools/` — tracked tool-dependency scripts

A new tracked folder. Each `ensure-<name>.sh` is an idempotent installer for one
tool. `bootstrap.sh` runs **every** `config/tools/ensure-*.sh` it finds (sorted),
after repo hydration. Adding a tool later = drop in `ensure-foo.sh`; re-hydrate
picks it up. No generic framework beyond the glob loop (YAGNI).

### `config/tools/ensure-rtk.sh`

Idempotent, POSIX `sh`-safe, `$HOME`-relative (no hardcoded user/paths beyond
`$HOME`). Steps:

1. **Binary.** `command -v rtk` → if found, report "rtk present" and skip install.
   If missing: run the curl install script, then prepend `~/.local/bin` to `PATH`
   for the remainder of the run so `rtk` is immediately callable.
2. **Hook wiring.** Guard: `grep -q rtk "$HOME/.claude/settings.json"` (2>/dev/null).
   If the hook is already registered → skip. Otherwise: print a notice that the
   global `~/.claude/settings.json` will be modified, then run `rtk init -g`.
3. Print: "Restart Claude Code for the RTK hook to activate."

Exit non-zero on a genuine failure (binary install failed, or `rtk` still not on
PATH after install). The grep-guard makes step 2 safe to re-run on every bootstrap.

### `bootstrap.sh` changes

After the manifest clone loop and before the summary:

- Glob `config/tools/ensure-*.sh` (sorted). For each: run it. Increment a
  `tools_ok` counter on success, `tools_failed` on non-zero exit, printing a ⚠ for
  failures.
- A tool failure does **not** abort bootstrap — repo hydration is the primary job.
  The final summary line gains `tools=<ok>/<total>`; the script's overall exit
  status remains governed by clone failures (existing behavior), not tool failures
  (which are surfaced as warnings).

## Error Handling

| Condition | Behavior |
| --- | --- |
| No network / curl fails | `ensure-rtk.sh` exits non-zero; bootstrap prints ⚠ and continues. |
| `rtk` missing from PATH after install | exit non-zero; ⚠. User told to add `~/.local/bin` to PATH. |
| Hook already in `~/.claude/settings.json` | `rtk init -g` skipped (idempotent). |
| `rtk` already on PATH | install skipped. |

## Testing

`ensure-rtk.sh` honors an overridable `$HOME`, enabling tests against a throwaway
temp HOME — **no writes to the real `~/.claude/settings.json` and no real install
during development**:

- **Skip-when-present:** with a fake `rtk` on `PATH`, assert the install branch is
  not taken.
- **Init-skip:** with a temp `$HOME/.claude/settings.json` already containing
  `rtk`, assert `rtk init -g` is not invoked.
- **bootstrap loop:** a dummy `config/tools/ensure-*.sh` (e.g. one that exits 0 and
  one that exits 1) verifies the loop runs all scripts, counts ok/failed, and does
  not abort on a tool failure.

The real install + `rtk init -g` runs only when the user runs `./bootstrap.sh` for
real on a device.

## Docs

- `config/README.md`: add a `tools/` row to the path table.
- `config/tools/README.md`: explain the `ensure-*.sh` convention (idempotent,
  `$HOME`-relative, run by bootstrap after repo hydration).

## Out of Scope

- Pinning RTK to a specific version (install script tracks `master`).
- Per-project RTK config / `config.toml` customization.
- GEMINI parity (added when Gemini is wired, per existing pattern).
