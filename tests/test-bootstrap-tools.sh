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
