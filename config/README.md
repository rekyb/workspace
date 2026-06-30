# config/ — portable agent configuration

Tracked in the workspace meta-repo, so it ships with every `git clone` (no
bootstrap needed for this folder).

| Path | Holds |
| ---- | ----- |
| `agents/` | All agent definitions. Global — available to every project. |
| `commands/` | All slash commands. Global — available to every project. |
| `mcp/` | MCP server configs. |
| `tools/` | Idempotent tool installers (`ensure-<name>.sh`), run by `bootstrap.sh` after repo hydration. |
| `conventions/<type>/rules.md` | Project-type rules/guidelines the AI follows (web, android, …). Rules only — no agents/commands here. |

## Conventions

A code repo opts into a convention via the optional 3rd column in `manifest`
(e.g. `repo/my-app  <url>  web`). On `./bootstrap.sh`, the convention's
`rules.md` is symlinked into the cloned repo as a local, untracked
`CLAUDE.local.md` — the code repo's own tracked files are never modified.

`GEMINI.local.md` parity is added when Gemini is first wired.
