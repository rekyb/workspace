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
