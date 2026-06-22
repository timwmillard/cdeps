#!/bin/sh
# test.sh — end-to-end smoke test for cdeps. Requires network (clones a small
# repo + fetches a raw header). Run via `make test`.
set -eu

CDEPS="$(pwd)/cdeps"
[ -x "$CDEPS" ] || { echo "build cdeps first (make)"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cdeps-test-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

cat > deps.lua <<'EOF'
return {
  { "zserge/jsmn", files = { "jsmn.h" } },
  { url = "https://raw.githubusercontent.com/nothings/stb/master/stb_perlin.h" },
}
EOF

echo "# sync"
"$CDEPS"
test -f deps/jsmn.h        || { echo "FAIL: jsmn.h missing"; exit 1; }
test -f deps/stb_perlin.h  || { echo "FAIL: stb_perlin.h missing"; exit 1; }
test -f deps.lock          || { echo "FAIL: deps.lock missing"; exit 1; }

echo "# verify"
"$CDEPS" verify

echo "# tamper detection"
echo "// tamper" >> deps/jsmn.h
if "$CDEPS" verify 2>/dev/null; then echo "FAIL: tamper not detected"; exit 1; fi

echo "# dogfood: rm -rf deps && cdeps restores from lock"
rm -rf deps
"$CDEPS"
"$CDEPS" verify

echo "# remove"
"$CDEPS" remove stb_perlin
test ! -f deps/stb_perlin.h || { echo "FAIL: stb_perlin.h not removed"; exit 1; }

echo "ALL OK"
