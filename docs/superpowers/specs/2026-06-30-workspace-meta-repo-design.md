# Workspace Meta-Repo — Design

- **Date:** 2026-06-30
- **Status:** approved
- **Topic:** Turn `/home/reky/workspace` into a thin coordination meta-repo (edbot-workspace pattern) that re-hydrates itself on a new device.

## Goal

Make `~/workspace` a git repo I can `git clone` onto any device and, with one
bootstrap step, be working immediately — without re-configuring anything. The
heavy / independently-versioned folders (`brain`, `archives`, `repo`) are
**gitignored** here and re-cloned from their own remotes. The scaffolding
(config, scripts, manifest, agent config) is **tracked** so it travels with the
clone.

## Reference

Modeled on `edbot-workspace` (see brain note *Edbot Workspace (Meta-Repo)*): a
meta-repo tracks only shared tooling + docs; the real repos live inside it but
are their own git repos, gitignored, cloned in separately, and listed in a
manifest.

## On-disk layout

```
workspace/
  README.md                 # tracked — what this is + how to bootstrap
  CLAUDE.md                 # tracked — agent guidance for the meta-repo
  bootstrap.sh              # tracked — re-hydration script
  manifest                  # tracked — list of gitignored repos + URLs + convention type
  .gitignore                # tracked

  config/                   # tracked — portable agent config
    agents/                 #   ALL agents (global, always available)
    commands/               #   ALL slash commands (global, always available)
    mcp/                    #   MCP server configs
    conventions/            #   per-project-type RULES/GUIDELINES only (markdown)
      web/
        rules.md            #     web dev rules + guidelines for the AI
      android/
        rules.md            #     android dev rules + guidelines for the AI
      README.md
    README.md

  .claude/
    settings.local.json     # tracked — permission allowlist (no secrets)
  .obsidian/                # tracked — Obsidian config (minus workspace.json)

  docs/superpowers/specs/   # tracked — this spec + future ones

  # --- gitignored, re-hydrated by bootstrap.sh ---
  brain/                    # clone of github.com/rekyb/brain.git
  archives/                 # clone of github.com/rekyb/archives.git
  repo/                     # clones listed in manifest (empty template for now)
```

## Tracked vs. gitignored

**Tracked (travels with `git clone`):**
`README.md`, `CLAUDE.md`, `bootstrap.sh`, `manifest`, `config/`,
`.claude/settings.local.json`, `.obsidian/` (excluding `workspace.json`),
`.gitignore`, `docs/`.

**Gitignored (re-hydrated):** `brain/`, `archives/`, `repo/`.

`.gitignore` also excludes `.obsidian/workspace.json` (noisy UI cursor-state)
while keeping the rest of `.obsidian/`.

## `manifest` format

One repo per line: `<dest-path>  <clone-url>  [convention-type]`.
`brain` and `archives` are real entries so bootstrap is one uniform loop.
`repo/*` lines are commented examples to fill in later; the optional third
column names a convention bundle from `config/conventions/`.

```
# dest-path            clone-url                                  convention
brain                  https://github.com/rekyb/brain.git
archives               https://github.com/rekyb/archives.git
# repo/my-web-app      git@github.com:rekyb/my-web-app.git        web
# repo/my-android      git@github.com:rekyb/my-android.git        android
```

Lines starting with `#` and blank lines are ignored.

## `bootstrap.sh` behavior

Idempotent and re-runnable. Reads `manifest` line by line:

1. Skip blank/comment lines.
2. Parse `dest`, `url`, optional `convention`.
3. If `dest/.git` already exists → skip with a note (no pull, to avoid surprises).
4. Else `mkdir -p` the parent (e.g. `repo/`) and `git clone <url> <dest>`.
5. If a `convention` is given → **link the convention into the cloned repo**
   (Option B, below).

Exit non-zero if any clone fails; print a summary of cloned / skipped / failed.

Usage on a fresh device:

```bash
git clone git@github.com:rekyb/workspace.git
cd workspace
./bootstrap.sh
```

## Convention loading — Option B (bootstrap symlinks)

A convention is **only rules/guidelines** — project-type-specific markdown the AI
should follow (e.g. web dev conventions, android dev conventions). Agents and
commands are **global** (`config/agents/`, `config/commands/`) and are not
project-type-specific, so they are never bundled into a convention.

Chosen over the "import line in the project's CLAUDE.md" approach so that the
cloned code repos stay clean (no edits to their tracked files).

When a manifest entry names a convention type, after cloning bootstrap surfaces
that convention's rules to the AI for that repo via a **local, untracked**
pointer — never via the repo's tracked `CLAUDE.md`:

- `config/conventions/<type>/rules.md` → linked/copied into the cloned repo as a
  local untracked rules file the agent reads (e.g. a `CLAUDE.local.md` symlink,
  or a link under `.claude/`), local to the device and untracked by the code repo.

Global agents/commands are made available independently of conventions (always
on); their wiring is not part of per-repo bootstrap. GEMINI.md support is
parallel (`.gemini/` / `GEMINI.local.md`) and added when first needed.

> Note: the precise local-pointer mechanism (symlink vs. copy, exact filename)
> is finalized during implementation against how Claude Code currently discovers
> local rules files.

## Hosting & setup steps

1. `git init` in `~/workspace`.
2. Create `.gitignore`, `manifest`, `bootstrap.sh`, `README.md`, `CLAUDE.md`,
   and the `config/` tree (with `web`/`android` convention stubs).
3. Verify `brain/`, `archives/`, `repo/` are ignored and that
   `.claude/settings.local.json` + `.obsidian/` are tracked.
4. Initial commit.
5. Create empty `github.com/rekyb/workspace` (private) and add it as `origin`.
6. Push.

## Daily lifecycle

- **New device:** `git clone …/workspace` → `./bootstrap.sh` → everything present.
- **Add a project:** add a line to `manifest` (with convention type) → re-run
  `bootstrap.sh` → commit the manifest change to the meta-repo.
- **Work:** edits inside `brain/` / `archives/` / `repo/<project>/` commit to
  *their own* repos. The meta-repo is only committed when scaffolding changes
  (manifest, scripts, `config/`, docs).

## Open decisions

None blocking. Convention loader is **Option B**; the exact symlink targets are
finalized during implementation. Gemini (`.gemini/`) parity deferred to first use.

## YAGNI / out of scope

- No edbot-style multi-repo CLI (`nb`/`sb`/`wpush`…). Bootstrap-only.
- No auto-pull/update of already-cloned repos (skip-if-exists is intentional).
- No secrets handling — `settings.local.json` is allowlist-only today; if
  secrets ever appear, switch to an untracked `.envrc.local` pattern.
