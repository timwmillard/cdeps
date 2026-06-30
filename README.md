# cdeps

A small CLI that **vendors C/C++ dependencies** into your source tree from a
declarative Lua config, recording exact pins **plus file hashes** in a lockfile.

After `cdeps` runs, every dependency file lives in your repo. Commit them, and
anyone who clones can build with **no extra download step and no dependency on
cdeps**. It's `go mod vendor` ergonomics for the world of single-header C
libraries and amalgamations.

```lua
-- deps.lua
return {
  config = { dir = "deps" },   -- each dep gets its own deps/<name>/ folder (subdir defaults to true)

  { "floooh/sokol", files = { "sokol_app.h", "sokol_gfx.h", "sokol_glue.h" } },  -- -> deps/sokol/*.h
  { "nothings/stb", files = { "stb_image.h" } },                                 -- -> deps/stb/stb_image.h
  { "recp/cglm", tag = "v0.9.4", files = { "include/**" } },                     -- -> deps/cglm/include/cglm/*.h
}
```

```console
$ cdeps          # vendors the files into deps/ and writes deps.lock
```

## Why

Single-header libraries and amalgamations (sokol, stb, miniaudio, sqlite, …) are
usually pulled in with ad-hoc `wget`/`curl` rules in a Makefile, or by manually
copying files and forgetting where they came from. There's no record of *which*
version you have and no way to tell if a file was tampered with.

cdeps replaces that with a declarative manifest and a committed lockfile:

- **Declare intent once** in `deps.lua` (GitHub `user/repo` by default, Lazy-style).
- **Pin exactly** — commit, tag, version, or default-branch HEAD — resolved to a
  concrete commit in `deps.lock`.
- **Verify integrity** — every vendored file is hashed; `cdeps verify` catches
  drift or tampering, making it a cheap CI gate.
- **Build offline** — the build system consumes the vendored files like any other
  source. cdeps is a setup-time tool only; it is never invoked by the build and
  generates no build glue.

## Install

cdeps is a single self-contained binary (a thin C shell with the logic in
embedded Lua bytecode — see [Design](#design)). Build it with `make`:

```console
$ make
$ make install            # copies ./cdeps to /usr/local/bin (override PREFIX=)
```

Requires a C compiler and `make`. The Lua runtime is vendored under
`deps/lua-5.5.0` and built in — there's no dependency on a system Lua.

**Runtime tools** cdeps shells out to: `git` (git transport), `curl`
(archive/file transport), and `tar`/`unzip` (archive extraction).

**Platform:** macOS and Linux. Windows is out of scope (the native helpers are
POSIX-only); MSYS2/Git-Bash may work incidentally, untested.

## Usage

```
cdeps [install|sync]        vendor anything in deps.lua missing from the tree
cdeps add <user/repo|url>   scaffold a spec, vendor it, update the lock
cdeps update [name]         re-resolve refs, re-fetch, re-hash, rewrite lock
cdeps verify                re-hash deps/ against the lock (CI gate)
cdeps remove <name>         delete owned files + drop from the lock
cdeps tidy                  reconcile deps.lua <-> lock <-> deps/
cdeps help                  show this help
  -y, --yes                 assume yes for update confirmations
```

Bare `cdeps` is the default verb: install/sync from `deps.lua` + `deps.lock`,
fetching only what's missing (a no-op when the committed tree is intact).

## The `deps.lua` config

A Lua file returning a list of specs. The **array part** is the spec list; an
optional **`config` key** holds global settings (mirrors Lazy's "specs + opts").

```lua
return {
  -- base dir (default "."); each dep gets its own deps/<name>/ via subdir (default true)
  config = { dir = "deps" },

  -- github user/repo, default branch, fetch the listed files -> deps/sokol/*.h
  { "floooh/sokol", files = { "sokol_app.h", "sokol_gfx.h" } },

  -- pin: commit > tag > version (semver) > default branch HEAD
  -- `include/**` keeps its subdir paths (flatten defaults to false); add
  -- `flatten = true` to vendor matched files by basename only. -> deps/cglm/include/cglm/*
  { "recp/cglm", tag = "v0.9.4", files = { "include/**" } },
  { "g-truc/glm", commit = "0af55cc" },     -- no files -> whole repo into deps/glm

  -- full url override (non-github host)
  { url = "https://gitlab.com/bztsrc/jsonc.git", files = { "jsonc.c" } },

  -- archive: download + extract + filter (transport auto-detected by extension)
  { url = "https://sqlite.org/2025/sqlite-amalgamation-3500400.zip",
    files = { "sqlite3.c", "sqlite3.h" } },

  -- single file: just download
  { url = "https://raw.githubusercontent.com/x/y/master/single.h" },

  -- dest override (with files, output is flat in the given dir)
  { "floooh/sokol", files = { "sokol_gfx.h" }, dest = "third_party" },
}
```

### Spec fields

| field          | meaning                                              | default                        |
|----------------|------------------------------------------------------|--------------------------------|
| `[1]`          | `"user/repo"` shorthand                              | — (or use `url`)               |
| `url`          | full URL; overrides the shorthand                    | `https://github.com/<u/r>.git` |
| `name`         | dep identity: lock key + CLI handle + default `<dir>/<name>` dir. **Must be unique** across entries (two entries from one repo each need their own `name`). | repo name (git) / repo segment of a GitHub archive URL / filename stem |
| `branch`/`tag`/`commit`/`version` | the pin (`version` = semver)      | remote default branch HEAD     |
| `files`        | glob filter (`**`, `*`); keep only matches           | keep everything                |
| `dir`          | base dir for *this* entry; overrides `config.dir`, still feeds `subdir`/`name` | `config.dir` (or `.`)          |
| `dest`         | output dir (literal project-relative path); overrides `dir`+`subdir` | see below                      |
| `subdir`       | give this dep its own `<dir>/<name>` folder vs. flat into `<dir>/` | `true` (or `config.subdir`)    |
| `flatten`      | `true` keeps only the basename; `false` preserves matched files' subdir paths | `false` (or `config.flatten`) |
| `strip_prefix` | archive: drop a leading path component               | auto (single top-level dir)    |
| `submodules`   | git: recurse submodules so their files vendor too    | `true`                         |
| `build`        | `function(ctx)` post-fetch compile/codegen hook      | none                           |

**Transport** is auto-detected from the resolved URL: `.git` / `user/repo` →
git (blobless clone + checkout pin); `.tar.gz`/`.tgz`/`.tar.bz2`/`.zip` → archive
(download + extract); anything else → file (download single file).

**Default `dest`** is driven by `subdir` (default `true`):

- **`subdir = true`** → each dep gets its own folder `<dir>/<name>` (e.g.
  `deps/sokol/sokol_gfx.h`, `deps/raylib/...`).
- **`subdir = false`** → all deps land flat in `<dir>/` (e.g. `deps/sokol_gfx.h`).

where `<dir>` is the entry's `dir` (per-entry, else `config.dir`, else `.`) and
`<name>` is the spec's `name` (auto-derived if unset). A per-entry `dest` overrides
the whole path entirely, ignoring `dir`/`subdir`. (`subdir` is the *inter*-dep
layout — a folder per dep; `flatten` is the *intra*-dep layout — whether a matched
file keeps its own subpath. They compose: `subdir=true, flatten=true` →
`deps/sokol/sokol_nuklear.h`.)

**Splitting one repo across destinations.** To send different files from a single
repo to different places, use one entry per destination — but give each a distinct
`name` (the lock key / CLI handle must be unique; cdeps errors on a collision):

```lua
{ "you/lib", files = { "lib/base.h" } },                       -- -> deps/base.h
{ "you/lib", name = "lib-tools", dir = "tool",                 -- -> tool/bin2c.c, …
  files = { "tool/bin2c/bin2c.c", "tool/sql2c/sql2c.c" } },
```

The blobless clone is cached, so the second entry reuses the first's fetch.

### Global config

| config key | meaning                                                       | default |
|------------|---------------------------------------------------------------|---------|
| `dir`      | base directory the default `dest` is built against            | `"."`   |
| `subdir`   | give each dep its own `<dir>/<name>` folder (per-entry `subdir` wins) | `true`  |
| `flatten`  | default `flatten` for every entry (per-entry `flatten` wins)  | `false` |

## The lockfile

`deps.lock` is a Lua table (cdeps `dofile`s it) that records, for each dep, the
resolved `commit` plus a content hash — a per-file list (`files` deps) or a
whole-tree digest (whole-repo git deps). It's deterministic and meant to be
**committed**:

- On any fetch of a *pinned* ref, if the recomputed hash ≠ the lock, cdeps stops
  and warns (force-moved tag, rewritten upstream, lying mirror).
- The committed lock is your checksum DB — a permanent, reviewable, trust-on-
  first-use record shared by everyone who clones. (No central server, unlike Go.)
- cdeps never executes code shipped by a dependency. The only hook (`build`) is
  author-written in your own `deps.lua`.

## Vendored vs fetch-mode

cdeps always does the same thing — fetch into `dest`, write `deps.lock`. What you
*commit* decides the model:

- **Vendored (the aim):** commit `deps/` + `deps.lua` + `deps.lock`. Clone → build
  with no tooling, no network, no cdeps. Resilient to upstream disappearing, and
  `cdeps update` shows real source diffs in review.
- **Fetch-mode:** gitignore `deps/`, commit only `deps.lua` + `deps.lock`; run
  `cdeps` after clone to repopulate. Smaller repo, but needs cdeps + network on
  first setup. The committed lock makes it reproducible (like npm + lockfile).

cdeps prefers neither, but warns (doesn't error) if its `dest` is gitignored —
usually that means you think you're vendoring but nothing is committed.

## Consuming the deps

cdeps emits no build glue; you wire it up by hand, once, over plain vendored files:

```cmake
# loose files (single-header / amalgamation)
target_include_directories(app PRIVATE deps)
target_sources(app PRIVATE deps/sqlite3.c)

# whole repo that ships its own build
add_subdirectory(deps/raylib)
target_link_libraries(app PRIVATE raylib)
```

## Design

cdeps is **a thin C shell embedding Lua, with the logic in `cdeps.lua`**. Lua is
required at runtime anyway — `deps.lua` can contain functions and computed config,
and `deps.lock` is itself a Lua table — so the orchestration (shell out to
git/curl/tar, walk/copy/hash files, glob, serialize) lives in Lua, and C provides
only the runtime plus the few primitives Lua's stdlib lacks (sha256, a little
filesystem traversal). `cdeps.lua` is precompiled with `luac` and embedded as
bytecode, so the result is one self-contained binary.

cdeps fetches through a **persistent cache** (`~/.cache/cdeps/`, honors
`XDG_CACHE_HOME`) for speed, stages each fetch in a throwaway tmp dir, then copies
the filtered files into `dest`. The cache changes speed, never outcome — the
lock's `commit`/`sha256` fully determine what gets vendored, so it's safe to
delete at any time.

cdeps **manages its own dependency** (the Lua runtime), dogfooding the tool:
`rm -rf deps && cdeps` restores everything, Lua included, from `deps.lua` +
`deps.lock`. The built binary embeds its own Lua, so `deps/lua-5.5.0` is only a
*build* input — the binary can repopulate the very dir that held its source.

**Dev loop:** set `CDEPS_DEV=1` to load `cdeps.lua` from disk (no rebuild needed
for logic changes), or run `lua cdeps.lua <cmd>` under a system Lua. Rebuild the C
shell only when adding a native primitive.

See [docs/PLAN.md](docs/PLAN.md) for the full design and
[docs/TODO.md](docs/TODO.md) for the current implementation status. A real-world
config is in [examples/deps.lua](examples/deps.lua).

## Inspiration

The config ergonomics are borrowed from
[Lazy.nvim](https://github.com/folke/lazy.nvim): the positional `"user/repo"`
shorthand, GitHub by default, the `branch`/`tag`/`commit`/`version` pins, and the
"specs + opts" table split (the array part is the spec list, the `config` key
holds settings). cdeps extends it with transport auto-detection (git/archive/file)
since, unlike Lazy, it isn't git-only.

The integrity model is borrowed from [Go modules](https://go.dev/ref/mod): cdeps
is closest to `go mod vendor` — copy deps into the tree, build offline from them,
with a manifest plus checksums. A committed lockfile as a trust-on-first-use
checksum DB, immutable-pin tamper detection, and running no code shipped by a
dependency all come from there — minus Go's server-side machinery, because the
lock is committed and the files are vendored.

## License

MIT — see [LICENSE](LICENSE).
