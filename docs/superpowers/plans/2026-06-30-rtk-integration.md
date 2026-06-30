# RTK Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `./bootstrap.sh` auto-install the RTK binary and wire its Claude Code hook on a fresh device, via a new tracked `config/tools/` mechanism.

**Architecture:** A new tracked folder `config/tools/` holds idempotent `ensure-<name>.sh` installers. `bootstrap.sh` runs every `config/tools/ensure-*.sh` (sorted) after repo hydration. `ensure-rtk.sh` installs `rtk` via its curl script if missing, then runs `rtk init -g` (announcing the global `~/.claude/settings.json` side-effect) unless the hook is already registered.

**Tech Stack:** POSIX `sh` / Bash. No new dependencies. Tests are plain Bash scripts run with `bash`.

## Global Constraints

- RTK is a **tool dependency**, not a repo — it does NOT go in `manifest`.
- Install method is the curl script ONLY: `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh` (installs to `~/.local/bin`).
- Hook wiring is `rtk init -g`, which modifies the **global** `~/.claude/settings.json` — bootstrap MUST print a notice before doing so. Never silent.
- All scripts are `$HOME`-relative — no hardcoded usernames or absolute paths beyond `$HOME`.
- Idempotent: re-running bootstrap skips an already-installed binary and an already-registered hook.
- A tool-install failure prints a ⚠ and does NOT abort bootstrap; the script's exit status stays governed by clone failures only (existing behavior).
- Tests must NOT run real `curl` or real `rtk init -g` against the real `~/.claude/settings.json` — they use a temp `$HOME` and a fake `rtk`.

---

### Task 1: `config/tools/ensure-rtk.sh` + tests

**Files:**
- Create: `config/tools/ensure-rtk.sh`
- Create: `tests/test-ensure-rtk.sh`

**Interfaces:**
- Consumes: nothing (entry point invoked by bootstrap).
- Produces: an executable `config/tools/ensure-rtk.sh` that exits 0 on success, non-zero on install failure. Reads `$HOME` for `~/.claude/settings.json` and `~/.local/bin`. Honors `$RTK_LOG` only via the fake `rtk` used in tests (the real script doesn't reference it).

- [ ] **Step 1: Write the failing test**

Create `tests/test-ensure-rtk.sh`:

```bash
#!/usr/bin/env bash
# Tests for config/tools/ensure-rtk.sh. Run: bash tests/test-ensure-rtk.sh
# Uses a temp $HOME and a fake `rtk` so NO real curl/install/init ever runs.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENSURE="$ROOT/config/tools/ensure-rtk.sh"
fail=0

make_fake_rtk() {
  # $1 = bin dir. Fake rtk logs any `init` invocation to $RTK_LOG.
  cat > "$1/rtk" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "init" ]; then echo "init $*" >> "$RTK_LOG"; fi
exit 0
EOF
  chmod +x "$1/rtk"
}

# --- Test 1: binary present + hook already registered -> full skip ---
tmp=$(mktemp -d); bin="$tmp/bin"; mkdir -p "$bin" "$tmp/home/.claude"
make_fake_rtk "$bin"
printf '{"hooks":{"PreToolUse":[{"command":"rtk-rewrite.sh"}]}}' > "$tmp/home/.claude/settings.json"
export RTK_LOG="$tmp/rtk.log"; : > "$RTK_LOG"
out=$(HOME="$tmp/home" PATH="$bin:$PATH" bash "$ENSURE" 2>&1)
if echo "$out" | grep -q "installing rtk"; then echo "FAIL t1: unexpected install"; fail=1; fi
if [ -s "$RTK_LOG" ]; then echo "FAIL t1: rtk init was called"; fail=1; fi
if ! echo "$out" | grep -q "already registered"; then echo "FAIL t1: missing skip msg"; echo "$out"; fail=1; fi
[ "$fail" -eq 0 ] && echo "PASS t1: full skip path"
rm -rf "$tmp"

# --- Test 2: binary present + hook NOT registered -> runs `rtk init -g` ---
tmp=$(mktemp -d); bin="$tmp/bin"; mkdir -p "$bin" "$tmp/home/.claude"
make_fake_rtk "$bin"
printf '{"hooks":{}}' > "$tmp/home/.claude/settings.json"
export RTK_LOG="$tmp/rtk.log"; : > "$RTK_LOG"
out=$(HOME="$tmp/home" PATH="$bin:$PATH" bash "$ENSURE" 2>&1)
if echo "$out" | grep -q "installing rtk"; then echo "FAIL t2: unexpected install"; fail=1; fi
if ! grep -q "init" "$RTK_LOG"; then echo "FAIL t2: rtk init NOT called"; fail=1; fi
if ! echo "$out" | grep -q "modifies your GLOBAL"; then echo "FAIL t2: missing global-side-effect notice"; fail=1; fi
[ "$fail" -eq 0 ] && echo "PASS t2: init-when-absent path"
rm -rf "$tmp"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-ensure-rtk.sh`
Expected: FAIL — `config/tools/ensure-rtk.sh` does not exist yet (bash: cannot open … No such file), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `config/tools/ensure-rtk.sh`:

```sh
#!/usr/bin/env sh
# Idempotent installer for RTK (Rust Token Killer) + its Claude Code hook.
# Run by bootstrap.sh. POSIX sh, $HOME-relative, safe to re-run.
set -eu

RTK_INSTALL_URL="https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"
SETTINGS="$HOME/.claude/settings.json"

# 1. Ensure the rtk binary is on PATH.
if command -v rtk >/dev/null 2>&1; then
  echo "= rtk present ($(command -v rtk))"
else
  echo "+ installing rtk via curl install script"
  curl -fsSL "$RTK_INSTALL_URL" | sh
  # The install script drops the binary in ~/.local/bin.
  PATH="$HOME/.local/bin:$PATH"
  export PATH
  if ! command -v rtk >/dev/null 2>&1; then
    echo "  ! rtk still not on PATH after install — add ~/.local/bin to your PATH" >&2
    exit 1
  fi
fi

# 2. Wire the Claude Code PreToolUse hook (global). Skip if already registered.
if grep -q rtk "$SETTINGS" 2>/dev/null; then
  echo "= rtk hook already registered in $SETTINGS"
else
  echo "  ⚠ running 'rtk init -g' — this modifies your GLOBAL $SETTINGS"
  rtk init -g
  echo "  → restart Claude Code for the RTK hook to activate"
fi
```

Then make it executable:

```bash
chmod +x config/tools/ensure-rtk.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-ensure-rtk.sh`
Expected: PASS — prints `PASS t1: full skip path`, `PASS t2: init-when-absent path`, `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add config/tools/ensure-rtk.sh tests/test-ensure-rtk.sh
git commit -m "feat: ensure-rtk.sh — idempotent RTK install + hook wiring"
```

**Note for reviewer:** the curl install branch (binary missing) is intentionally NOT unit-tested — it would hit the network and perform a real install. It is exercised only by a real `./bootstrap.sh` on a device without rtk. Both tested paths keep a fake `rtk` on PATH so install is skipped.

---

### Task 2: `bootstrap.sh` tool-runner loop + integration test

**Files:**
- Modify: `bootstrap.sh` (insert tool loop after the manifest `while` loop, before `echo "---"`; extend the summary line)
- Create: `tests/test-bootstrap-tools.sh`

**Interfaces:**
- Consumes: `config/tools/ensure-*.sh` scripts (from Task 1 and future tools).
- Produces: bootstrap that runs each tool script, counts `tools_ok`/`tools_total`, warns on failure without aborting, and prints `tools=<ok>/<total>` in the summary.

- [ ] **Step 1: Write the failing test**

Create `tests/test-bootstrap-tools.sh`:

```bash
#!/usr/bin/env bash
# Tests bootstrap.sh runs config/tools/ensure-*.sh and tolerates tool failure.
# Run: bash tests/test-bootstrap-tools.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

tmp=$(mktemp -d)
cp "$ROOT/bootstrap.sh" "$tmp/bootstrap.sh"
printf '# empty manifest (only comments) — no repos to clone\n' > "$tmp/manifest"
mkdir -p "$tmp/config/tools"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/config/tools/ensure-ok.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/config/tools/ensure-fail.sh"
chmod +x "$tmp/config/tools/"*.sh

out=$(cd "$tmp" && bash bootstrap.sh 2>&1); rc=$?

if [ "$rc" -ne 0 ]; then echo "FAIL: exit $rc — tool failure must not abort bootstrap"; fail=1; fi
if ! echo "$out" | grep -q "tools=1/2"; then echo "FAIL: summary missing 'tools=1/2'"; echo "$out"; fail=1; fi
if ! echo "$out" | grep -q "tool failed: ensure-fail.sh"; then echo "FAIL: missing failure warning"; fail=1; fi

rm -rf "$tmp"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-bootstrap-tools.sh`
Expected: FAIL — current `bootstrap.sh` has no tool loop, so `tools=1/2` is absent (test prints `FAIL: summary missing 'tools=1/2'`), exit 1.

- [ ] **Step 3: Write minimal implementation**

In `bootstrap.sh`, the manifest loop currently ends like this:

```sh
done < <(grep -vE '^\s*#|^\s*$' "$MANIFEST")

echo "---"
echo "cloned=$cloned skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
```

Replace that trailing block with:

```sh
done < <(grep -vE '^\s*#|^\s*$' "$MANIFEST")

# --- Tool dependencies: run every config/tools/ensure-*.sh (sorted) ---
tools_ok=0 tools_total=0
for tool in "$ROOT"/config/tools/ensure-*.sh; do
  [ -e "$tool" ] || continue          # no matches: glob stays literal, skip
  tools_total=$((tools_total+1))
  echo "» tool: $(basename "$tool")"
  if bash "$tool"; then
    tools_ok=$((tools_ok+1))
  else
    echo "  ⚠ tool failed: $(basename "$tool")" >&2
  fi
done

echo "---"
echo "cloned=$cloned skipped=$skipped failed=$failed tools=$tools_ok/$tools_total"
[ "$failed" -eq 0 ]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-bootstrap-tools.sh`
Expected: PASS — `ALL PASS`, exit 0.

Run the Task 1 test too (no regression): `bash tests/test-ensure-rtk.sh`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/test-bootstrap-tools.sh
git commit -m "feat: bootstrap runs config/tools/ensure-*.sh after repo hydration"
```

---

### Task 3: Documentation

**Files:**
- Modify: `config/README.md` (add `tools/` row to the path table)
- Create: `config/tools/README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: docs describing the `config/tools/ensure-*.sh` convention.

- [ ] **Step 1: Add the `tools/` row to `config/README.md`**

`config/README.md` contains this table:

```markdown
| Path | Holds |
| ---- | ----- |
| `agents/` | All agent definitions. Global — available to every project. |
| `commands/` | All slash commands. Global — available to every project. |
| `mcp/` | MCP server configs. |
| `conventions/<type>/rules.md` | Project-type rules/guidelines the AI follows (web, android, …). Rules only — no agents/commands here. |
```

Add one row immediately after the `mcp/` row so the table reads:

```markdown
| `mcp/` | MCP server configs. |
| `tools/` | Idempotent tool installers (`ensure-<name>.sh`), run by `bootstrap.sh` after repo hydration. |
| `conventions/<type>/rules.md` | Project-type rules/guidelines the AI follows (web, android, …). Rules only — no agents/commands here. |
```

- [ ] **Step 2: Create `config/tools/README.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add config/README.md config/tools/README.md
git commit -m "docs: document config/tools/ convention and ensure-rtk"
```

---

## Self-Review

**Spec coverage:**
- `config/tools/` mechanism → Task 1 (folder + first script) + Task 2 (bootstrap loop). ✓
- `ensure-rtk.sh` binary install via curl → Task 1, Step 3. ✓
- Hook wiring via `rtk init -g` with grep-guard + announced global side-effect → Task 1, Step 3. ✓
- Bootstrap runs `ensure-*.sh` after hydration, counts, non-aborting → Task 2. ✓
- `$HOME`-overridable for testing; no real curl/init in tests → Task 1 tests. ✓
- Docs (`config/README.md` row + `config/tools/README.md`) → Task 3. ✓
- Error-handling table (curl fail, PATH miss, already-registered, already-present) → covered by `ensure-rtk.sh` branches in Task 1, Step 3. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/vague steps. All code shown in full. ✓

**Type consistency:** `tools_ok`/`tools_total` names consistent between Task 2 implementation and its test's `tools=1/2` assertion. `RTK_LOG` used consistently in Task 1 test (fake rtk writes it, asserts on it); the real `ensure-rtk.sh` never references `RTK_LOG`. Settings path `~/.claude/settings.json` consistent across script, tests, and docs. ✓
