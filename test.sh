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
  -- default dir is now "."; pin to deps/ for this test. subdir defaults to true
  -- (a folder per dep); this test asserts flat paths, so opt out with subdir=false.
  config = { dir = "deps", subdir = false },
  { "zserge/jsmn", files = { "jsmn.h" } },
  { url = "https://raw.githubusercontent.com/nothings/stb/master/stb_perlin.h" },
  -- whole-repo vendor (no `files`): locked by tree digest, not a per-file list.
  -- subdir=true (overriding the global false) so it owns deps/Hello-World/ — a
  -- tree-digest dep must own its dest dir, not share the flat one.
  { url = "https://github.com/octocat/Hello-World.git", subdir = true,
    commit = "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" },
}
EOF

echo "# sync"
"$CDEPS" install
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

echo "# dogfood: rm -rf deps && cdeps install restores from lock"
rm -rf deps
"$CDEPS" install
"$CDEPS" verify

echo "# remove"
"$CDEPS" remove stb_perlin
test ! -f deps/stb_perlin.h || { echo "FAIL: stb_perlin.h not removed"; exit 1; }

echo "# dev: local-folder override (no network)"
DEVSRC="$TMP/local-cbase"
mkdir -p "$DEVSRC/lib"
echo "// base v1" > "$DEVSRC/lib/base.h"
cat > deps.lua <<EOF
return {
  config = { dir = "deps", subdir = false, flatten = true },
  { "timwmillard/cbase", dev = "$DEVSRC", files = { "lib/base.h" } },
}
EOF
"$CDEPS" install
grep -q "v1" deps/base.h            || { echo "FAIL: dev file not copied"; exit 1; }
grep -q 'dev = ' deps.lock          || { echo "FAIL: lock missing dev marker"; exit 1; }
grep -q 'sha256' deps.lock          && { echo "FAIL: dev entry recorded a hash"; exit 1; }
echo "// base v2" > "$DEVSRC/lib/base.h"
"$CDEPS" install                    # re-copies from local on every run
grep -q "v2" deps/base.h            || { echo "FAIL: dev edit did not resync"; exit 1; }
"$CDEPS" verify                     # must pass (dev entries are skipped, not hashed)

echo "ALL OK"
