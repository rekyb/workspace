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
  installer="$(mktemp)"
  if ! curl -fsSL "$RTK_INSTALL_URL" -o "$installer"; then
    rm -f "$installer"
    echo "  ! rtk download failed (network/URL?) — see $RTK_INSTALL_URL" >&2
    exit 1
  fi
  sh "$installer"
  rm -f "$installer"
  # The install script drops the binary in ~/.local/bin.
  PATH="$HOME/.local/bin:$PATH"
  export PATH
  if ! command -v rtk >/dev/null 2>&1; then
    echo "  ! rtk still not on PATH after install — add ~/.local/bin to your PATH" >&2
    exit 1
  fi
  echo "  → installed rtk to ~/.local/bin — add it to your shell PATH so future runs skip reinstall"
fi

# 2. Wire the Claude Code PreToolUse hook (global). Skip if already registered.
if grep -q rtk "$SETTINGS" 2>/dev/null; then
  echo "= rtk hook already registered in $SETTINGS"
else
  echo "  ⚠ running 'rtk init -g' — this modifies your GLOBAL $SETTINGS"
  rtk init -g
  echo "  → restart Claude Code for the RTK hook to activate"
fi
