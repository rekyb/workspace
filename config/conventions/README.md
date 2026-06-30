# conventions/

Each subfolder is a project type and contains **only** `rules.md` — the
rules and guidelines the AI follows when doing agentic development in a repo of
that type. No agents or commands live here; those are global in `config/agents/`
and `config/commands/`.

A repo selects a convention via the 3rd column in the workspace `manifest`.
`bootstrap.sh` links the chosen `rules.md` into the cloned repo as
`CLAUDE.local.md` (local + untracked).

To add a type: `mkdir config/conventions/<type>` and write its `rules.md`.
