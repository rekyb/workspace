# Workspace Meta-Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/home/reky/workspace` into a thin git meta-repo that re-hydrates its gitignored content (`brain`, `archives`, `repo`) on any device via one bootstrap step.

**Architecture:** The workspace is a coordination repo (edbot-workspace pattern). It tracks only scaffolding — `bootstrap.sh`, a `manifest` of repos to clone, portable agent `config/`, and machine config (`.claude/settings.local.json`, `.obsidian/`). Heavy/independently-versioned folders are gitignored and re-cloned from their own GitHub remotes by `bootstrap.sh`, which reads `manifest`. A manifest entry may name a per-project-type convention whose `rules.md` bootstrap links into the cloned repo locally.

**Tech Stack:** Bash, git, POSIX shell tooling. No build system, no test framework — verification is by running `bootstrap.sh` and inspecting `git status` / filesystem.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-30-workspace-meta-repo-design.md`.
- Working directory is `/home/reky/workspace` throughout.
- Gitignored (must NOT be tracked): `brain/`, `archives/`, `repo/`.
- Tracked: `README.md`, `CLAUDE.md`, `bootstrap.sh`, `manifest`, `config/`, `.claude/settings.local.json`, `.obsidian/` (excluding `workspace.json`), `.gitignore`, `docs/`.
- Manifest clone URLs use **HTTPS** (`https://github.com/rekyb/...`).
- `bootstrap.sh` is idempotent and **skips already-cloned repos** (no pull).
- Conventions hold **only** `rules.md` (markdown). All agents/commands live globally in `config/agents/` and `config/commands/`, never inside a convention.
- Meta-repo remote: `https://github.com/rekyb/workspace.git` (created by the user; wired up but pushed by the user).
- `bootstrap.sh` must be executable (`chmod +x`).

---

### Task 1: `.gitignore` — define tracked vs. ignored boundary

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: the ignore rules every later task relies on so `brain/`/`archives/`/`repo/` never get staged.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Re-hydrated by bootstrap.sh from `manifest` — never tracked here.
/brain/
/archives/
/repo/

# Obsidian: keep shared config, drop noisy per-device UI state.
.obsidian/workspace.json
.obsidian/workspace-mobile.json

# OS / editor cruft
.DS_Store
*.swp

# Scratch
/scratch/
/.superpowers/
```

- [ ] **Step 2: Verify the ignore rules resolve as intended**

Run: `git init -q 2>/dev/null; git check-ignore -v brain archives repo .obsidian/workspace.json README.md 2>&1; echo "---"; git check-ignore .obsidian/app.json README.md; echo "exit=$?"`

Expected: `brain`, `archives`, `repo`, and `.obsidian/workspace.json` each print a matching `.gitignore` line; the final `git check-ignore` prints nothing and `exit=1` (meaning `.obsidian/app.json` and `README.md` are NOT ignored).

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add meta-repo .gitignore (ignore brain/archives/repo)"
```

---

### Task 2: `manifest` — repo list for bootstrap

**Files:**
- Create: `manifest`

**Interfaces:**
- Consumes: nothing.
- Produces: the data file `bootstrap.sh` (Task 3) parses. Format per line: `<dest-path>  <clone-url>  [convention]`. `#` and blank lines ignored.

- [ ] **Step 1: Write `manifest`**

```
# Workspace re-hydration manifest.
# Format:  <dest-path>  <clone-url>  [convention]
#   dest-path   where to clone (relative to workspace root)
#   clone-url   git remote (HTTPS)
#   convention  optional; a folder under config/conventions/ whose rules.md
#               bootstrap links into the cloned repo locally
# Lines starting with # and blank lines are ignored.

brain       https://github.com/rekyb/brain.git
archives    https://github.com/rekyb/archives.git

# Add code projects below, e.g.:
# repo/my-web-app   https://github.com/rekyb/my-web-app.git   web
# repo/my-android   https://github.com/rekyb/my-android.git   android
```

- [ ] **Step 2: Verify parseable rows**

Run: `grep -vE '^\s*#|^\s*$' manifest | awk '{print NF": "$0}'`

Expected: exactly two lines, each starting with `2: ` (two fields) — the `brain` and `archives` entries. No commented examples appear.

- [ ] **Step 3: Commit**

```bash
git add manifest
git commit -m "feat: add re-hydration manifest (brain, archives)"
```

---

### Task 3: `bootstrap.sh` — re-hydration script

**Files:**
- Create: `bootstrap.sh`

**Interfaces:**
- Consumes: `manifest` (Task 2) and, when a row has a convention, `config/conventions/<type>/rules.md` (Task 4).
- Produces: an executable `./bootstrap.sh` that clones missing repos and links convention rules. Function of record: `link_convention <dest> <type>` symlinks `config/conventions/<type>/rules.md` → `<dest>/CLAUDE.local.md`.

- [ ] **Step 1: Write `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Re-hydrate the workspace meta-repo: clone every repo listed in `manifest`
# and link any named convention's rules into the cloned repo (local, untracked).
# Idempotent: existing clones are skipped (no pull).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/manifest"
cloned=0 skipped=0 failed=0

link_convention() {
  # link_convention <dest-abs> <type>
  local dest="$1" type="$2"
  local rules="$ROOT/config/conventions/$type/rules.md"
  if [ ! -f "$rules" ]; then
    echo "  ! convention '$type' has no rules.md ($rules) — skipping link"
    return 0
  fi
  ln -sfn "$rules" "$dest/CLAUDE.local.md"
  echo "  → linked convention '$type' rules → $dest/CLAUDE.local.md"
}

[ -f "$MANIFEST" ] || { echo "No manifest at $MANIFEST" >&2; exit 1; }

while read -r dest url convention; do
  [ -z "${dest:-}" ] && continue
  case "$dest" in \#*) continue ;; esac
  abs="$ROOT/$dest"
  if [ -d "$abs/.git" ]; then
    echo "= skip   $dest (already cloned)"
    skipped=$((skipped+1))
  else
    echo "+ clone  $dest  <-  $url"
    mkdir -p "$(dirname "$abs")"
    if git clone "$url" "$abs"; then
      cloned=$((cloned+1))
    else
      echo "  ! clone failed: $dest" >&2
      failed=$((failed+1))
      continue
    fi
  fi
  [ -n "${convention:-}" ] && link_convention "$abs" "$convention"
done < <(grep -vE '^\s*#|^\s*$' "$MANIFEST")

echo "---"
echo "cloned=$cloned skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bootstrap.sh && ls -l bootstrap.sh`
Expected: permissions show `-rwxr-xr-x` (the `x` bits set).

- [ ] **Step 3: Syntax-check the script**

Run: `bash -n bootstrap.sh && echo "syntax-ok"`
Expected: prints `syntax-ok` with no errors.

- [ ] **Step 4: Dry verification of the manifest parser (no real clone)**

Run:
```bash
grep -vE '^\s*#|^\s*$' manifest | while read -r dest url convention; do
  echo "would handle: dest='$dest' url='$url' conv='${convention:-}'"
done
```
Expected: two `would handle:` lines for `brain` and `archives`, each with the correct HTTPS url and empty `conv=''`.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add idempotent bootstrap.sh (clone from manifest + link conventions)"
```

---

### Task 4: `config/` tree — global agents/commands/mcp + convention stubs

**Files:**
- Create: `config/README.md`
- Create: `config/agents/.gitkeep`
- Create: `config/commands/.gitkeep`
- Create: `config/mcp/.gitkeep`
- Create: `config/conventions/README.md`
- Create: `config/conventions/web/rules.md`
- Create: `config/conventions/android/rules.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `config/conventions/<type>/rules.md` files that `bootstrap.sh`'s `link_convention` (Task 3) links into cloned repos. `web` and `android` are the seed types.

- [ ] **Step 1: Write `config/README.md`**

```markdown
# config/ — portable agent configuration

Tracked in the workspace meta-repo, so it ships with every `git clone` (no
bootstrap needed for this folder).

| Path | Holds |
| ---- | ----- |
| `agents/` | All agent definitions. Global — available to every project. |
| `commands/` | All slash commands. Global — available to every project. |
| `mcp/` | MCP server configs. |
| `conventions/<type>/rules.md` | Project-type rules/guidelines the AI follows (web, android, …). Rules only — no agents/commands here. |

## Conventions

A code repo opts into a convention via the optional 3rd column in `manifest`
(e.g. `repo/my-app  <url>  web`). On `./bootstrap.sh`, the convention's
`rules.md` is symlinked into the cloned repo as a local, untracked
`CLAUDE.local.md` — the code repo's own tracked files are never modified.

`GEMINI.local.md` parity is added when Gemini is first wired.
```

- [ ] **Step 2: Create the global folders with `.gitkeep` placeholders**

Run:
```bash
mkdir -p config/agents config/commands config/mcp config/conventions/web config/conventions/android
touch config/agents/.gitkeep config/commands/.gitkeep config/mcp/.gitkeep
```
Expected: no output; folders now exist (verified in Step 5).

- [ ] **Step 3: Write `config/conventions/README.md`**

```markdown
# conventions/

Each subfolder is a project type and contains **only** `rules.md` — the
rules and guidelines the AI follows when doing agentic development in a repo of
that type. No agents or commands live here; those are global in `config/agents/`
and `config/commands/`.

A repo selects a convention via the 3rd column in the workspace `manifest`.
`bootstrap.sh` links the chosen `rules.md` into the cloned repo as
`CLAUDE.local.md` (local + untracked).

To add a type: `mkdir conventions/<type>` and write its `rules.md`.
```

- [ ] **Step 4: Write the convention rule stubs**

`config/conventions/web/rules.md`:
```markdown
# Web Development Conventions

> Rules and guidelines the AI follows for web projects. Fill in as patterns settle.

## Stack & structure
- (TODO: framework, package manager, folder layout)

## Coding rules
- (TODO: linting, formatting, component conventions)

## Testing
- (TODO: test runner, coverage expectations)
```

`config/conventions/android/rules.md`:
```markdown
# Android Development Conventions

> Rules and guidelines the AI follows for android projects. Fill in as patterns settle.

## Stack & structure
- (TODO: language, build system, module layout)

## Coding rules
- (TODO: lint rules, architecture pattern)

## Testing
- (TODO: test framework, instrumentation)
```

- [ ] **Step 5: Verify the tree**

Run: `find config -type f | sort`
Expected (exactly these):
```
config/README.md
config/agents/.gitkeep
config/commands/.gitkeep
config/conventions/README.md
config/conventions/android/rules.md
config/conventions/web/rules.md
config/mcp/.gitkeep
```

- [ ] **Step 6: Commit**

```bash
git add config
git commit -m "feat: add config/ (global agents/commands/mcp + web/android convention stubs)"
```

---

### Task 5: `README.md` + `CLAUDE.md` — meta-repo docs

**Files:**
- Create: `README.md`
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: references `bootstrap.sh`, `manifest`, `config/` from prior tasks.
- Produces: human + agent entry-point docs. No downstream code depends on these.

- [ ] **Step 1: Write `README.md`**

```markdown
# workspace

A thin **coordination meta-repo**. It is not an application — it tracks only
scaffolding (scripts, manifest, config, docs). The heavy folders (`brain`,
`archives`, `repo`) are gitignored and re-cloned from their own GitHub remotes.

## New device

```bash
git clone https://github.com/rekyb/workspace.git
cd workspace
./bootstrap.sh
```

`bootstrap.sh` reads `manifest` and clones every listed repo (`brain`,
`archives`, and anything under `repo/`). It is idempotent — re-running skips
repos that are already cloned.

## Layout

| Path | Tracked? | Holds |
| ---- | -------- | ----- |
| `bootstrap.sh` | yes | Re-hydration script |
| `manifest` | yes | Repos to clone (+ optional convention) |
| `config/` | yes | Portable agent config (agents, commands, mcp, conventions) |
| `.claude/settings.local.json` | yes | Permission allowlist |
| `.obsidian/` | yes | Obsidian config (minus `workspace.json`) |
| `docs/` | yes | Specs and plans |
| `brain/` | no (cloned) | Obsidian knowledge vault |
| `archives/` | no (cloned) | Project graveyard (zips) |
| `repo/` | no (cloned) | Active code project clones |

## Add a project

1. Add a line to `manifest`: `repo/<name>  <https-clone-url>  [convention]`
2. `./bootstrap.sh`
3. `git commit` the manifest change.
```

- [ ] **Step 2: Write `CLAUDE.md`**

```markdown
# CLAUDE.md — workspace meta-repo

This repo coordinates several independent repos; it holds **no application code**.

## What's tracked here
Only scaffolding: `bootstrap.sh`, `manifest`, `config/`, `.claude/`, `.obsidian/`,
`docs/`. Everything else (`brain/`, `archives/`, `repo/*`) is gitignored and is a
**separate git repo** — commit changes to those inside their own repo, never here.

## Commit scope
- Scaffolding change (manifest, scripts, config, docs) → commit to THIS repo.
- Content change inside `brain/`, `archives/`, `repo/<x>/` → commit in that repo.

## Re-hydration
`./bootstrap.sh` clones everything in `manifest` (idempotent, skips existing).
A manifest row's optional 3rd column names a convention under
`config/conventions/<type>/`; its `rules.md` is symlinked into the cloned repo as
`CLAUDE.local.md` (local, untracked) — global agents/commands live in `config/`.

## Where things are
- Knowledge/context/specs vault: `brain/` (its own repo).
- Portable agent config: `config/`.
- Specs & plans for this repo: `docs/superpowers/`.
```

- [ ] **Step 3: Verify both files exist and reference real paths**

Run: `ls README.md CLAUDE.md && grep -l bootstrap.sh README.md CLAUDE.md`
Expected: both files listed, and both contain `bootstrap.sh`.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add meta-repo README and CLAUDE.md"
```

---

### Task 6: Track machine config + final verification

**Files:**
- Modify (stage existing): `.claude/settings.local.json`
- Modify (stage existing): `.obsidian/app.json`, `.obsidian/appearance.json`, `.obsidian/core-plugins.json`

**Interfaces:**
- Consumes: `.gitignore` from Task 1 (must keep these tracked while ignoring `workspace.json`).
- Produces: a committed repo where machine config travels with the clone. Terminal deliverable.

- [ ] **Step 1: Confirm machine config will be tracked and UI-state ignored**

Run: `git check-ignore .obsidian/workspace.json; echo "ws exit=$?"; git check-ignore .claude/settings.local.json .obsidian/app.json; echo "config exit=$?"`

Expected: first line prints `.obsidian/workspace.json` with `ws exit=0` (ignored); second `git check-ignore` prints nothing with `config exit=1` (NOT ignored — will be tracked).

- [ ] **Step 2: Stage machine config**

Run: `git add .claude/settings.local.json .obsidian/`
Then: `git status --short`
Expected: `.claude/settings.local.json` and the non-`workspace.json` `.obsidian/*` files appear as staged (`A`); `.obsidian/workspace.json` does NOT appear.

- [ ] **Step 3: Full-repo guard — ensure no gitignored content leaked in**

Run: `git add -A && git status --short | grep -E '^[AM] +(brain|archives|repo)/' && echo "LEAK!" || echo "clean (no brain/archives/repo staged)"`
Expected: prints `clean (no brain/archives/repo staged)`.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: track machine config (.claude permissions, .obsidian)"
```

- [ ] **Step 5: Final tree sanity check**

Run: `git ls-files | grep -vE '^(docs|config)/' | sort`
Expected (top-level tracked set, excluding docs/ and config/):
```
.claude/settings.local.json
.gitignore
.obsidian/app.json
.obsidian/appearance.json
.obsidian/core-plugins.json
CLAUDE.md
README.md
bootstrap.sh
manifest
```
(No `brain/`, `archives/`, `repo/`, or `.obsidian/workspace.json`.)

---

### Task 7: Wire the GitHub remote

**Files:** none (git config only).

**Interfaces:**
- Consumes: the committed repo from Task 6.
- Produces: an `origin` remote pointed at `https://github.com/rekyb/workspace.git`. The user performs the actual `git push` (and creates the empty GitHub repo first).

- [ ] **Step 1: Pause for the user to create the empty GitHub repo**

Tell the user: create an empty **private** repo at `github.com/rekyb/workspace` (no README/`.gitignore`/license, to avoid a divergent first commit). Wait for confirmation.

- [ ] **Step 2: Add the remote (idempotent)**

Run: `git remote get-url origin 2>/dev/null && git remote set-url origin https://github.com/rekyb/workspace.git || git remote add origin https://github.com/rekyb/workspace.git; git remote -v`
Expected: `origin` lists `https://github.com/rekyb/workspace.git` for both fetch and push.

- [ ] **Step 3: Confirm branch name and hand off the push to the user**

Run: `git branch --show-current`
Then tell the user the exact push command to run themselves (e.g. `git push -u origin main`), since pushing is their step per the spec. Do not push automatically.

---

## Self-Review

**Spec coverage:**
- Tracked/ignored boundary → Task 1 (`.gitignore`) + Task 6 (machine config tracked).
- `manifest` format incl. convention column → Task 2.
- Idempotent skip-if-exists bootstrap → Task 3.
- `config/` with global agents/commands/mcp + conventions = rules-only → Task 4.
- Option B convention loading (symlink `rules.md` → `CLAUDE.local.md`, code repos untouched) → Task 3 `link_convention` + Task 4 stubs.
- README/CLAUDE docs → Task 5.
- HTTPS clone URLs → Task 2 manifest + Global Constraints.
- Hosting on `rekyb/workspace`, push by user → Task 7.
- figma-design removed → not in any task (correctly absent).
- YAGNI: no multi-repo CLI, no auto-pull → honored (no such tasks).

**Placeholder scan:** The `(TODO: …)` lines in Task 4 convention stubs are intentional *content* of user-authored rule files (the spec defines conventions as stubs to fill later), not plan placeholders — every plan step itself shows complete content and exact commands.

**Type/name consistency:** `manifest` 3-column format, `link_convention <dest> <type>`, `CLAUDE.local.md` target, and `config/conventions/<type>/rules.md` path are used identically across Tasks 2, 3, 4, and 5.
