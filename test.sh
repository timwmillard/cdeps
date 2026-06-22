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
  config = { dir = "deps" },   -- default dir is now "."; pin to deps/ for this test
  { "zserge/jsmn", files = { "jsmn.h" } },
  { url = "https://raw.githubusercontent.com/nothings/stb/master/stb_perlin.h" },
  -- whole-repo vendor (no `files`): locked by tree digest, not a per-file list
  { url = "https://github.com/octocat/Hello-World.git",
    commit = "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" },
}
EOF

echo "# sync"
"$CDEPS"
test -f deps/jsmn.h               || { echo "FAIL: jsmn.h missing"; exit 1; }
test -f deps/stb_perlin.h         || { echo "FAIL: stb_perlin.h missing"; exit 1; }
test -f deps/Hello-World/README   || { echo "FAIL: whole-repo tree missing"; exit 1; }
test -f deps.lock                 || { echo "FAIL: deps.lock missing"; exit 1; }
grep -q tree_sha256 deps.lock     || { echo "FAIL: tree digest not in lock"; exit 1; }
grep -q 'README.*sha256' deps.lock && { echo "FAIL: whole-repo wrote a per-file list"; exit 1; }

echo "# verify"
"$CDEPS" verify

echo "# tamper detection"
echo "// tamper" >> deps/jsmn.h
if "$CDEPS" verify 2>/dev/null; then echo "FAIL: tamper not detected"; exit 1; fi

echo "# tamper detection (whole-repo tree digest)"
echo "tamper" >> deps/Hello-World/README
if "$CDEPS" verify 2>/dev/null; then echo "FAIL: tree tamper not detected"; exit 1; fi
# the dogfood step below (rm -rf deps) restores both tampered trees

echo "# dogfood: rm -rf deps && cdeps restores from lock"
rm -rf deps
"$CDEPS"
"$CDEPS" verify

echo "# remove"
"$CDEPS" remove stb_perlin
test ! -f deps/stb_perlin.h || { echo "FAIL: stb_perlin.h not removed"; exit 1; }

echo "ALL OK"
