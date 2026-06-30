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
