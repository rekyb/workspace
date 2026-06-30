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
