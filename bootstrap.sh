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
