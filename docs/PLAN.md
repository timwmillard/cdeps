# cdeps — vendored dependency manager

A small CLI that vendors C/C++ dependencies into a project's source tree from a
Lazy.nvim-style Lua config, recording exact pins + file hashes in a lockfile.

## Goal & philosophy

- **Vendored, committed deps (the aim).** After `cdeps` runs, every dependency
  file lives in the repo and is committed. Other developers clone and build with
  **no extra download step** and **no dependency on cdeps**. (Whether to actually
  commit `deps/` is a per-project choice — see Vendored vs fetch-mode below.)
- **cdeps is a setup-time tool only.** It is used to *add*, *update*, *remove*,
  and *verify* deps. It is never invoked by the build.
- **The build system consumes vendored files like any other source.** cdeps
  emits no CMake/Make/build glue (Option A). You wire `target_include_directories`
  / `target_sources` by hand, once.
- **Config as simple as possible** — copy Lazy.nvim ergonomics: positional
  `"user/repo"`, GitHub by default, everything else optional.

### Two separated concerns

1. **Acquisition** (cdeps' job): resolve a ref → pin, download, extract, filter,
   vendor into `dest`, hash, write lock. The build never does this.
2. **Consumption** (build's job): include dirs, compile sources, defines. Plain,
   hand-written, over ordinary vendored files.

### Vendored vs fetch-mode (a per-project choice, not the tool's)

cdeps always does the same thing — fetch into `dest` and write `deps.lock`. What a
project commits decides the model, and the tool stays agnostic:

- **Vendored (the aim):** commit `deps/` + `deps.lua` + `deps.lock`. Clone → build,
  with **no tooling, no network, no cdeps** at build time. Resilient to upstream
  changes/disappearance, and `cdeps update` shows real source diffs in review.
- **Fetch-mode (valid alternative):** gitignore `deps/`, commit only `deps.lua` +
  `deps.lock`; run `cdeps` after clone to repopulate. The lock makes this
  **reproducible** — same as npm + lockfile, Cargo, Go modules. Smaller repo,
  cleaner diffs, at the cost of: cdeps (+ git/curl) required to build, network on
  first setup, and no protection if an upstream ref is deleted/moved.

Both are legitimate; the committed lock is what makes fetch-mode reproducible. cdeps
neither enforces nor prefers one — it just fetches and locks. Because the **default
goal is vendored**, an ignored `dest` dir is most often an accident (you think
you're vendoring but nothing's committed), so cdeps should **warn** (not error) if
its `dest` is gitignored — a nudge, easily silenced when fetch-mode is intentional.

## Config: `deps.lua`

Hand-written intent. A list of specs, Lazy-style (`[1]` = `"user/repo"`).

```lua
return {
  -- minimal: github user/repo, remote default branch, fetch the listed files
  { "floooh/sokol", files = { "sokol_app.h", "sokol_gfx.h", "sokol_glue.h" } },

  { "nothings/stb", files = { "stb_image.h" } },

  -- pin: commit > tag > version (semver range) > default branch HEAD
  { "recp/cglm",     tag = "v0.9.4", files = { "include/**" } },
  { "g-truc/glm",    commit = "0af55cc", files = { "glm/**" } },

  -- full url override (non-github git host)
  { url = "https://gitlab.com/foo/bar.git", files = { "bar.h" } },

  -- archive (auto-detected from extension): download + extract + filter.
  -- strip_prefix here is explicit; auto-strip would also drop the single top dir.
  { url = "https://sqlite.org/2024/sqlite-amalgamation-3450000.zip",
    strip_prefix = "sqlite-amalgamation-3450000",
    files = { "sqlite3.c", "sqlite3.h" }, dest = "deps/sqlite" },

  -- single file (auto-detected from extension): just download
  { url = "https://raw.githubusercontent.com/x/y/master/single.h" },

  -- dest escape hatch: literal path (== dir = "deps/sokol", subdir = false):
  { "floooh/sokol", files = { "sokol_gfx.h" }, dest = "deps/sokol" },   -- -> deps/sokol/sokol_gfx.h
  { "floooh/sokol", files = { "sokol_gfx.h" }, dest = "third_party" },  -- -> third_party/sokol_gfx.h

  -- post-fetch hook: compile/generate only, NOT extraction
  { "sqlite/sqlite", build = function(ctx) ctx.run("make sqlite3.c") end },
}
```

### Spec fields (mirrors Lazy where possible)

| field          | meaning                                        | default                         |
|----------------|------------------------------------------------|---------------------------------|
| `[1]`          | `"user/repo"` shorthand                        | — (or use `url`)                |
| `url`          | full URL; overrides shorthand                  | `https://github.com/<u/r>.git`  |
| `name`         | dep identity: lock key + CLI handle + default `<dir>/<name>` dir; **must be unique** (collision is an error) | repo name (git) / repo segment of a GitHub archive URL / filename stem |
| `branch`/`tag`/`commit`/`version` | the pin (`version` = semver range) | remote default branch HEAD   |
| `dev`          | local-dev override: copy from this local folder instead of fetching | off (fetch remotely) |
| `files`        | glob filter; keep only matches                 | keep everything                 |
| `strip_prefix` | archive: drop a leading path component         | none                            |
| `dir`          | base dir for this entry; overrides `config.dir`, still feeds `subdir`/`name` | `config.dir` (or `.`) |
| `dest`         | escape hatch: literal output dir, bypassing `dir`/`subdir`/`name` (== `dir = X, subdir = false`) | derived from `dir`+`subdir` (see Vendoring layout) |
| `subdir`       | own `<dir>/<name>` folder vs. flat into `<dir>/` | `true` (or `config.subdir`)    |
| `flatten`      | `true` keeps only the basename; `false` preserves matched files' subdir paths | `false` (or `config.flatten`) |
| `submodules`   | git: recurse submodules so their files vendor too | `true` (mirrors Lazy)        |
| `build`        | `function(ctx)` post-fetch compile/codegen     | none                            |

Deferred (not in first cut): `dependencies` (transitive vendoring — rabbit hole).

### Global config

A single optional `config` key in the same `deps.lua` (no second file). Lua tables
hold both an array part and named keys, so the **array part is the spec list** and
the **`config` key holds settings** (mirrors Lazy's "specs + opts" split):

```lua
return {
  config = { dir = "vendor" },   -- optional; all keys optional

  { "floooh/sokol", files = { "sokol_gfx.h" } },   -- -> vendor/sokol/sokol_gfx.h
  { "raysan5/raylib", tag = "5.5" },               -- -> vendor/raylib/...
}
```

| config key | meaning                                  | default  |
|------------|------------------------------------------|----------|
| `dir`      | base directory the default output layout is built from | `"."` |
| `subdir`   | give each dep its own `<dir>/<name>` folder (per-entry `subdir` wins) | `true` |
| `flatten`  | default `flatten` for every entry (per-entry `flatten` wins) | `false` |

`dir` + `subdir` fill in the **default** `dest`: `subdir` true → `<dir>/<name>`
(a folder per dep), false → `<dir>/` (all deps flat together). `flatten` sets the
project-wide default for matched files (basename-only when true); a per-entry
`flatten` still overrides it. These two axes are orthogonal — `subdir` is the
*inter*-dep layout, `flatten` the *intra*-dep one. Keep `config` a small,
extensible slot — don't add speculative knobs (a global `submodules`/cache path
can slot in later if a real need appears).

**`dest` precedence:** the layout is built from four composable knobs — `dir`,
`name`, `subdir`, `flatten` — which cover essentially every scenario. `dest` is an
**escape hatch**, not the primary knob: `dest = "X"` is exactly equivalent to
`dir = "X", subdir = false` (a literal project-relative path, **not** relative to
`dir`/`name`), just shorter and clearer for deliberate placements (e.g. `mate.h`'s
`dest = "."` at the project root, or the Lua amalgam's `dest = "deps/lua-5.5.0"`
pinning a folder name distinct from its lock `name = "lua"`). Since per-entry `dir`
is free-form, `dest` is technically redundant — keep it because the one-field form
reads as a clear "put it exactly here" override. Reach for the four knobs first.

## Transport auto-detection (cdeps extension beyond Lazy)

Lazy is git-only. cdeps picks the transport from the resolved URL, so no explicit
`kind` field is needed:

| resolved url ends in…             | transport | action                          |
|-----------------------------------|-----------|---------------------------------|
| `.git`, `git@…`, or `user/repo`   | `git`     | clone (blobless) + checkout pin |
| `.tar.gz`/`.tgz`/`.tar.bz2`/`.zip`| `archive` | download + extract              |
| any other `…/name.ext`            | `file`    | download single file            |
| (any, when `dev` is set)          | `local`   | copy from the local `dev` folder |

`files` (glob filter) and `dest`/layout apply uniformly after fetch for all four.

### Local dev override (`dev`, from Lazy)

`dev = "<path>"` on an entry sources from a local folder instead of fetching —
cdeps sets `transport = "local"` and uses the path as the staging `root`, so
`files`/`flatten`/`dir`/`subdir`/`dest` all behave identically to a fetched dep.
The declared `[1]`/`url` (if any) stays the dep's identity; `dev` only swaps the
source, so removing `dev` restores normal fetching (and a real pinned lock entry).
We **copy** rather than symlink — cdeps is a vendoring tool, so dev files are real
files in the tree (build works, no symlink-to-absolute-path footguns); `sync`
re-copies dev entries every run so local edits propagate. A dev source is local +
mutable, so it can't be a reproducible pin: the lock records only the vendored
paths (marked `dev = "<path>"`, no content hashes — stable across edits) and
`verify` skips dev entries.

### Shorthand resolution (copy from Lazy `fragments.lua:108`)

- `[1]` contains `/` and starts with `http`/`git@` → full URL.
- `[1]` contains `/` otherwise → `https://github.com/<u/r>.git`, name = part after `/`.
- name (for `dest`/lock key) = last path segment, trailing `.git` stripped.

## Acquisition mechanics

### git (the common case)

Copy Lazy's choices (`task/git.lua`):

- **Blobless clone, NOT `--depth 1`**: `git clone <url> --filter=blob:none
  --recurse-submodules -c core.autocrlf=false [-b <branch>] <tmp>`. Keeps full
  history so any tag/commit/version is checkout-able. (`--depth 1 -b <ref>` is a
  valid fast path only when pinning a *named* branch/tag, never a bare sha.)
- **Default branch via remote**, not hardcoded master/main: read
  `refs/remotes/origin/HEAD`.
- **Pin precedence**: `commit` → `tag` → `version` (semver match against tags) →
  default branch HEAD. Resolve to a concrete commit and record it.
- Checkout pin → copy working tree (filtered) into `dest` → discard tmp `.git`.
- **Submodules** (`submodules`, default on): recurse so submodule files vendor
  too. Useful when a dep *is* the version source for another — e.g. cimgui pins
  Dear ImGui as a submodule at `imgui/`; cloning cimgui recursively yields the
  exact imgui it expects, with no separate imgui pin to keep in sync. `files` can
  then select submodule paths (`imgui/imgui.h`, …); `flatten = false` preserves
  their subdirs. The lock records the superproject commit plus the vendoring
  hash (per-file list when `files` selects paths, else the whole-tree
  `tree_sha256`); it may also record submodule commits for provenance.

### Download location: cache + staging

cdeps fetches into a **persistent cache** outside the project, checks out / extracts
into a throwaway **staging** dir, then copies the filtered files into `dest`. The
project tree only ever contains vendored files + `deps.lock` — never a `.git` dir,
the cache, or unfiltered files.

- **Cache (`~/.cache/cdeps/`, required):** the working store of fetched bytes,
  shared across runs and projects. git → persistent blobless clones (`git fetch`
  deltas on later runs); archive/file → content-addressed downloads. This is
  **core, not a later optimization** — cdeps always fetches through the cache.
  (Location honors `XDG_CACHE_HOME`.)
- **Staging (throwaway tmp):** per-run checkout/extract/filter happens in a temp
  dir (e.g. `/tmp/cdeps-XXXXXX/`); filtered files are copied into `dest`, then it's
  discarded. The cache persists; staging does not.

The cache changes *speed*, never *outcome*: the lock's `commit`/`sha256` fully
determine what gets vendored, so the cache is safe to delete at any time (next run
repopulates it) and never affects reproducibility.

#### Cache design

Layout:

```
~/.cache/cdeps/
  git/<host>/<user>/<repo>/   # persistent blobless clone; `git fetch` deltas
  dl/<sha256-or-urlhash>      # downloaded archives & single files, content-addressed
```

Payoff by transport (general, but concentrated in git):

- **git** — biggest win: keep the blobless clone, `cdeps update` fetches deltas
  instead of re-cloning.
- **archive** — modest: skip re-downloading the tarball/zip. Archive URLs are
  usually version-pinned, so re-fetch only happens on a version bump anyway.
- **file** — negligible: a single raw header is tiny. Cached for uniformity, not
  for savings.

**Validity rule (mirrors `update`'s pinned-vs-floating split):** a cache hit is
only safe when you know it's current.

- **Pinned / immutable source** (commit-pinned, versioned archive URL, raw URL
  containing a sha): same key ⇒ same bytes forever. Hit is always valid — just
  confirm against the lock's `sha256`, no network needed.
- **Floating source** (branch HEAD, a `latest` archive, a `master` raw URL): the
  cached copy can be stale. Revalidate before trusting it — `git fetch` for git,
  re-download / HTTP conditional request for archive/file.

#### vs Go modules

Go's module cache (`$GOPATH/pkg/mod`) is three layers: `cache/vcs/` (git clones),
`cache/download/` (immutable per-version zips, content-addressed, checked against
`go.sum`), and `<module>@<version>/` (extracted, read-only source trees, **one per
version**). Go keeps a full extracted copy of *every* version because `pkg/mod`
**is the build input** — every project on the machine compiles directly against it,
so multiple versions must coexist on disk, read-only.

cdeps is the opposite: **the cache is never built against.** The build input is the
vendored copy inside the project (`deps/`); the cache only exists to *produce* that
copy fast, and its job ends once files are copied. So cdeps needs **no per-version
extracted trees** — nothing builds from them and no two versions coexist:

- **git → one blobless clone per repo**, `checkout` the pin into staging as needed.
  A blobless clone yields any tag/commit cheaply, so per-version copies would be
  pure waste. (≈ Go's `cache/vcs`.)
- **archive / file → content-addressed per artifact** (`dl/<sha256>`); naturally
  per-version since each version is a distinct URL/hash. (≈ Go's `cache/download`.)

So cdeps' cache = Go's vcs cache + download cache, **minus** the per-version
extracted trees — leaner, and correct because cdeps vendors into the project rather
than building from the cache. (Worth borrowing from Go: mark content-addressed
downloads read-only, a cheap integrity guard.)

### archive

Download to tmp → extract (`tar`/`unzip`) → apply `strip_prefix` → filter → copy.

`strip_prefix` peels off the leading wrapper directory that archives almost
always have (e.g. the sqlite zip extracts to `sqlite-amalgamation-3450000/…`;
a GitHub tarball extracts to `<repo>-<ref>/…`). Stripping it keeps `dest` paths
clean and stable across version bumps (so `#include` paths don't change when the
URL does). It runs *before* the `files` filter: reshape paths, then filter them.

**Auto-strip (planned):** for a GitHub archive the wrapper name is predictable —
`<repo>-<ref>` (e.g. `sokol-master`, or `sokol-<sha>` for a commit). cdeps can
derive `strip_prefix` automatically for GitHub-sourced archives instead of making
the user type it. A more general fallback: if the extracted archive has exactly
one top-level directory, strip it by default. An explicit `strip_prefix` always
overrides the auto-detected one.

### file

Download directly to `dest` (single or several raw URLs).

### `files` glob filter

Applied to the fetched tree before copying to `dest`; keep only matches
(`**`, `*` supported). Omit = keep everything.

### Vendoring layout (`dir` / `subdir`, `dest` as escape hatch)

The output location is built from `dir` + `subdir`, with `<dir>` = the entry's
`dir` (per-entry, else `config.dir`, default `.`):

- **`subdir = true`** (default) → each dep gets its own dir **`<dir>/<name>`**
  (`deps/sokol/sokol_gfx.h`, `deps/raylib/...`). Keeps deps from one another and
  is the only sane layout for a whole repo (dumping its tree flat into `<dir>/`
  would be a mess).
- **`subdir = false`** → all deps land flat in **`<dir>/`** (`deps/sokol_gfx.h`),
  for projects that want every header loose together (the old Makefile style).

This is a *default-only* convenience: it affects output location only (visible,
local — no effect on fetching/pinning/reproducibility). `dest` is the escape hatch
— a literal path that bypasses `dir`/`subdir`/`name`, equivalent to `dir = X,
subdir = false`. (Unlike transport, which is never inferred.)

```
-- subdir = true (default) -> a folder per dep
{ "floooh/sokol", files = { "sokol_app.h", "sokol_gfx.h", "sokol_glue.h" } }
  -> deps/sokol/sokol_app.h, deps/sokol/sokol_gfx.h, deps/sokol/sokol_glue.h
{ "raysan5/raylib", tag = "5.5" }   -> deps/raylib/...   (tree preserved)

-- subdir = false -> flat into <dir>/
{ "floooh/sokol", subdir = false, files = { "sokol_gfx.h" } }  -> deps/sokol_gfx.h

-- dest escape hatch (== dir = "third_party", subdir = false)
{ "floooh/sokol", ..., dest = "third_party" }  -> third_party/sokol_gfx.h, …
```

**Nested trees** (e.g. cglm's `include/cglm/*.h`): flattening would collide /
lose structure, so the default `flatten = false` preserves each matched file's
path relative to the fetched root (after `strip_prefix`, for archives). Opt into
`flatten = true` only for flat single-header sets that won't collide on basename:

```
{ "recp/cglm", files = { "include/**" }, dest = "deps/cglm" }
  -> deps/cglm/include/cglm/vec3.h, …
```

**Collisions:** with a shared flat `dest` (`subdir = false`, or several deps
pointing at the same explicit `dest`), two deps could produce the same filename.
Since the lock records every owned file path explicitly, cdeps can detect a
collision and error rather than silently overwrite. The fix is the default
`subdir = true`, or a per-dep `dest` (e.g. `dest = "deps/sokol"`).

### `build` hook

Runs **after** fetch, **before** hashing. Receives `ctx`:
- `ctx.src`  — tmp checkout/extract dir
- `ctx.dest` — vendored output dir
- `ctx.run`  — shell helper
- `ctx.copy` — filter-aware copy helper

For compile/generate/patch/rename only (e.g. run sqlite amalgamation). **Not** an
extraction mechanism (that's transport's job). Output files in `dest` are hashed
into the lock; the function's intent is opaque.

## Lockfile: `deps.lock`

Lazy's `{branch, commit}` pin **plus** a content hash for vendoring integrity.
Lua table (so cdeps can `dofile` it). Deterministic: sort dep keys and file lists.
Keys are dep names, quoted when not bare identifiers (`["lua-cjson"] = …`).

An entry records its vendored content one of two ways:

- **per-file list** (`files`) — when a `files` filter picks loose files into a
  *shared* dest (the default `.`, the current dir). The explicit list is how
  `remove`/`verify`/`tidy` know exactly which files cdeps owns and never clobber
  a user's file.
- **tree digest** (`tree_sha256`) — when a git repo is vendored *whole* (no
  `files`) into its own dedicated dest dir. The `commit` already pins every file's
  content (a commit SHA is a Merkle root over the full tree), so per-file hashes
  would be redundant for pinning; one Go-`h1:`-style dirhash over the dest tree is
  all `verify` needs, and it keeps the lock from ballooning to thousands of lines
  for a large repo. The dep owns its whole dest dir, so ownership is unambiguous
  without enumerating files.

```lua
-- deps.lock — generated by cdeps. Do not edit by hand.
return {
  lockfile_version = 1,
  sokol = {                      -- files filter -> per-file list
    url    = "https://github.com/floooh/sokol.git",
    branch = "master",          -- intent / tracked branch
    commit = "3c83f4f5…",       -- resolved pin (the Lazy part)
    dest   = ".",               -- default flat dest
    files  = {                  -- the vendoring part
      { path = "sokol_app.h",  sha256 = "ab12…" },
      { path = "sokol_gfx.h",  sha256 = "cd34…" },
      { path = "sokol_glue.h", sha256 = "ef56…" },
    },
  },
  glm = {                        -- whole git repo -> tree digest, no file list
    url         = "https://github.com/g-truc/glm.git",
    branch      = "master",
    commit      = "0af55cc…",   -- pins every file's content on its own
    dest        = "deps/glm",   -- dedicated dir, owned wholesale
    tree_sha256 = "7e1c…",      -- dirhash over the whole dest tree
  },
  sqlite = {                     -- archive -> per-file list (+ provenance hash)
    url            = "https://sqlite.org/2024/sqlite-amalgamation-3450000.zip",
    archive_sha256 = "99aa…",   -- provenance: hash of the downloaded archive
    dest           = "deps/sqlite",
    files = {
      { path = "deps/sqlite/sqlite3.c", sha256 = "…" },
      { path = "deps/sqlite/sqlite3.h", sha256 = "…" },
    },
  },
}
```

- **No globs in the lock** — `files` is the resolved, expanded file list.
- **git, whole repo** (no `files`): `commit` is the reproducible pin; `branch` is
  intent; `tree_sha256` is the verify digest. No per-file list.
- **git, `files` filter**: `commit` + `branch` + per-file list.
- **archive**: `archive_sha256` (what was downloaded) + per-file hashes (what
  landed) — extraction into a possibly-shared dest keeps the per-file list.
- **file**: per-file `url` + `sha256`.

## Integrity (Go-inspired)

cdeps is closest to `go mod vendor` (copy deps into the tree, build offline from
them, with a manifest + checksums). The integrity half of what makes Go modules
well-regarded transfers directly — without Go's server-side machinery — because
cdeps **commits the lock and vendors the files**.

1. **Tamper detection on pinned refs.** On any fetch/update of a *pinned* ref
   (`commit`, or a `tag`), if the recomputed hash ≠ the hash in `deps.lock`, **stop
   and warn** — the tag was force-moved, the upstream was rewritten, or a mirror is
   lying. This is the local equivalent of Go's immutable-version guarantee +
   checksum DB, at near-zero cost. (Floating refs legitimately change; only pinned
   ones trip this.)
2. **No execution of fetched code.** Go's biggest edge over npm: it runs no
   install/build scripts shipped *by a dependency* (npm's `postinstall` is a prime
   supply-chain vector). cdeps holds the same line — the `build` hook is
   **author-written in your own `deps.lua`**, never code pulled from the dep. cdeps
   never runs anything the upstream controls. Keep this invariant true.
3. **The committed lock is the checksum DB.** Go needs `sum.golang.org` because its
   cache is per-machine and ephemeral. cdeps' lock is committed in git — a
   permanent, reviewable, trust-on-first-use record of every dep's hashes, shared by
   everyone who clones. Same practical benefit (detect upstream content changing for
   a fixed version), no server.

A per-dep tree digest (à la Go's `h1:` dirhash) is already used as the *sole*
integrity record for whole-repo git deps (`tree_sha256`, see above) — there the
`commit` carries pinning and the dirhash carries verify. *Optional later:* compute
the same digest alongside the per-file list for `files`/archive deps too, so
`verify` can short-circuit on one hash and only fall to per-file on mismatch.

## Commands

```
cdeps                             # (no args) sync: vendor anything in deps.lua missing from the tree
cdeps add <user/repo|url> [opts]  # append spec to deps.lua, vendor, update lock
cdeps update [name]               # re-resolve ref→commit, re-fetch, re-hash, rewrite lock
cdeps verify                      # re-hash deps/ against lock; nonzero exit on mismatch (CI)
cdeps remove <name>               # delete owned files (from lock) + drop from deps.lua + lock
cdeps tidy                        # reconcile deps.lua <-> lock <-> deps/ (see below)
cdeps install                     # alias for the no-arg sync
```

`cdeps tidy` (à la `go mod tidy`) reconciles manifest with reality: drop lock
entries no longer in `deps.lua`, delete vendored files cdeps owns whose spec is
gone, and **warn** (never auto-delete) about files in the dest dir that no entry
owns — they might be yours. Keeps the tree honest as deps come and go.

Bare `cdeps` is the default verb — install/sync from `deps.lua` + `deps.lock`,
fetching only what's missing (a no-op when the committed tree is intact). This is
what the dogfood self-test (`rm -rf deps && cdeps`) relies on.

### `update` semantics

- **Pinned** (commit, or tag/version resolving to a fixed commit): re-fetch is a
  no-op unless the pin itself changes.
- **Floating** (branch HEAD): may legitimately change the commit/hashes. Show a
  diff and require confirmation before rewriting vendored files.

## Consumption (Option A — hand-written, not generated)

```cmake
# CMakeLists.txt — plain CMake over vendored files (default flat deps/)
target_include_directories(app PRIVATE deps)
target_sources(app PRIVATE deps/sqlite3.c)
# one TU defines SOKOL_IMPL etc. — exactly the special case codegen would leak

# whole-repo deps that ship their own build: add_subdirectory, don't hand-list
add_subdirectory(deps/raylib)   # vendored with no `files` filter, CMakeLists & all
target_link_libraries(app PRIVATE raylib)
```

Two consumption styles, by dep shape: **loose files** (single-header / amalgamation)
→ `target_include_directories` / `target_sources`; **whole repo with its own
CMakeLists** (vendored without a `files` filter) → `add_subdirectory`. Both are
plain hand-written CMake over vendored files — still no cdeps-generated build glue.

## Implementation / architecture

**A thin C shell embedding Lua, with the logic in `cdeps.lua`.** Lua is required at
runtime regardless — `deps.lua` can contain functions (`build`), computed config,
and `require` composition, so it must be *evaluated*, not parsed; `deps.lock` is
itself a Lua table we `dofile`. Given that, the work (shell out to git/curl/tar,
walk/copy/hash files, glob, serialize a table) is string + subprocess + file I/O —
trivial in Lua, tedious in C, and not performance-critical (bound by network/git).
So C is only the *runtime* + the few *primitives Lua lacks*; the logic lives in Lua.

### C / Lua split

- **`cdeps.c` (thin):** `main()`, create the Lua state, register the native module,
  run the embedded `cdeps.lua`. ~a few hundred lines; changes rarely.
- **`cdeps.lua` (thick):** spec resolution (shorthand→url, transport detection),
  orchestration of git/curl/tar, `files` filter / `flatten`, lock read/write, and
  the commands (`add`/`update`/`verify`/`remove`). All iteration happens here.

### Native module (only what Lua's stdlib can't do well)

| primitive | why not pure Lua |
|---|---|
| `sha256(path)` / `sha256_string(s)` | no hashing in stdlib; shelling to `shasum`/`sha256sum` is a macOS-vs-Linux mess. `sha256_string` hashes the dirhash manifest for `tree_sha256` |
| dir walk / recursive copy / `mkdir -p` / `rm -rf` | no filesystem traversal in stdlib |
| glob match | reused for `files`; cleaner than reimplementing in Lua |
| *(optional)* `exec` with captured stdout + exit code | `io.popen`/`os.execute` work; add only if clumsy |

### Embedding the Lua runtime

Vendor **full Lua source** (via cdeps itself — see the `lua/lua` example). Full Lua
brings `luac`, so precompile `cdeps.lua` to **bytecode** and embed that (bin2c'd
bytes), plus the full stdlib. `edubart/minilua` (single-header) is a lighter
alternative if a smaller footprint ever matters, but full Lua + `luac` bytecode is
the cleaner default. Either way the result is **one self-contained binary**, a
controlled Lua version, and no runtime dependency on a system Lua.

### Bootstrap (chicken-and-egg)

cdeps needs Lua to build, but cdeps fetches Lua — so the **first** Lua source is
acquired manually and **checked in** (committed under `deps/lua/`). No bootstrap
script. Build cdeps against the committed source; from then on Lua is just another
entry in cdeps' own `deps.lua`, managed by `cdeps update` like any dep. Downstream
users build straight from the committed source and never repeat the manual step.

**Self-test (dogfood):** once cdeps is built, `rm -rf deps && cdeps` should restore
everything — including Lua — from `deps.lua` + `deps.lock`. This works because the
built binary **embeds its own Lua** (bytecode + linked runtime): `deps/lua/` is only
a *build* input, never a *runtime* dependency, so the binary can repopulate the very
deps dir that contained its own Lua source. A clean proof that cdeps reproduces its
own dependency set.

### Dev loop & phasing

- **Iterate without recompiling:** load `cdeps.lua` from disk when `CDEPS_DEV=1`
  (or a sibling file exists), else use the embedded bytecode. Rebuild C only when
  adding a primitive.
- **Prototype first:** write `cdeps.lua` as a plain script under the system `lua`
  (shell to `shasum` temporarily) to validate the whole flow, then wrap it in the
  C shell + embedded Lua once the logic settles.

## Other tool dependencies

- `git` (git transport — accepted, same as Lazy)
- `curl` (archive/file transport)
- `tar` / `unzip` (archive extraction)

**Platform:** macOS/Linux first (shells out to the tools above). Windows is
out of scope for the first cut (git-bash/WSL may work incidentally, untested).

**Atomicity:** vendor each dep into a tmp dir and swap into place only on success,
and update a dep's lock entry only after its files land. A failed or interrupted
run then leaves the tree and lock consistent (the failed dep simply unchanged)
rather than half-written. Multi-dep runs are per-dep atomic, not all-or-nothing.

## Implementation phases

1. **Core loop, git + file transports, through the cache**: resolve spec → fetch
   into `~/.cache/cdeps` → stage → `files` filter → vendor → write `deps.lock`
   (with hashes). The cache is part of the core loop, not deferred. `deps.lua` with
   sokol as the live example.
2. **`verify`** against the lock (cheapest high-value safety net).
3. **archive transport** + `strip_prefix` (sqlite as the test case).
4. **`update`** with pinned/floating semantics + confirm-on-drift, including
   **tamper detection** (pinned-ref hash ≠ lock ⇒ stop and warn).
5. **`add` / `remove` / `tidy`** editing `deps.lua` + reconciling lock/`deps/`.
6. **`build` hook** execution + hashing of its outputs.
7. *(later)* `dependencies` (transitive vendoring); optional per-dep tree digest.

   *Not planned as an auto-behavior:* switching to GitHub raw-URL fetches when
   `files` is set. It would need GitHub API resolution anyway (ref→commit for
   pinning, tree listing for globs), add a host-specific second code path, and
   make transport depend implicitly on an unrelated field. Clone (blobless) +
   cache is cheap, host-agnostic, glob-capable, and pins for free. The explicit
   raw `url` (file transport) remains the opt-in escape for zero-clone deps.

## Open questions

- `version = "latest"` semantics: newest semver **tag** vs default-branch HEAD —
  define explicitly (reserve `latest` for newest tag; use a branch name for HEAD).
- Editing `deps.lua` programmatically (for `add`/`remove`) without trashing
  comments/formatting — may keep `add` as "scaffold, you fill in" initially.
- Central registry of known deps (original idea) — orthogonal; lock/schema don't
  depend on it. Defer.
