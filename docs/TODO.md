# cdeps — TODO / implementation gaps

Status of [PLAN.md](PLAN.md) against the current implementation. Split into work
the PLAN itself deferred (correctly absent) and gaps in in-scope features.

## Deferred by the PLAN (intentionally not done)

- [ ] **`dependencies`** — transitive vendoring. PLAN: "not in first cut."
- [ ] **Per-dep tree digest** (Go `h1:`-style fingerprint over a dep's whole
      fileset). PLAN: "optional later." Per-file hashes already cover correctness.
- [ ] **Auto-switch to GitHub raw-URL fetch when `files` is set.** PLAN: explicitly
      "not planned" — the explicit raw `url` (file transport) remains the opt-in.

## Gaps in in-scope features

### 1. Floating archive/file cache revalidation — missing (real bug)
`download()` reuses the cached file whenever it exists, unconditionally. A floating
raw URL (e.g. a `master` header) or a `latest` archive will **not re-fetch even on
`cdeps update`**. The PLAN's validity rule says floating archive/file sources must
revalidate (HTTP conditional request / re-download). Git floating refs *do*
revalidate via `git fetch`; archive/file do not. **Highest priority** — silently
breaks `update` for raw-URL and `latest` deps.

### 2. Tamper detection is git-only
A pinned *git* ref whose commit moved is flagged. A pinned *archive/file* (versioned
URL) is not checked — its re-fetched `archive_sha256` / file hashes are not compared
against the lock. PLAN wanted tamper detection on "any pinned ref."

### 3. Atomicity weaker than specified
PLAN: vendor each dep into a tmp dir and **swap into place only on success**. Current
code copies files straight into `dest`, then writes the lock once at the end. The
lock stays consistent on failure (not written if a dep dies), but a mid-copy failure
can leave a **half-written dep** in the tree — no per-dep staging swap.

### 4. `version` semver is minimal
Only exact match and `"latest"` (newest tag). No range/caret/tilde matching, which
`version = "semver range"` implies. Also resolve the open question: reserve `latest`
for newest tag; use a branch name for default-branch HEAD.

### 5. `update` shows a commit delta, not a source diff
PLAN: "Show a diff and require confirmation." Current code prints
`oldcommit -> newcommit` and prompts; it does not show the actual file changes.

### 6. `add`/`remove` don't really edit `deps.lua`
`remove` deletes files + the lock entry but only *warns* you to drop the spec;
`add` does a naive append with no field scaffolding. (PLAN flagged programmatic
`deps.lua` editing — preserving comments/formatting — as an open question.)

### 7. Cache not content-addressed by sha256
Downloads are named by a djb2 hash of the URL, not `dl/<sha256>`, and are not marked
read-only (the PLAN's cheap integrity guard borrowed from Go).

### 8. Minor lock fidelity
For the file transport the URL is recorded at the dep level, not per-file `url` as
the PLAN's file example shows.

## Deviations that are not functional gaps

- **Glob lives in Lua, not the native module.** PLAN listed it as a native primitive;
  `**`/`*`/`?` are implemented in Lua. Works fine — a placement choice.
- **`exec` with captured stdout** native primitive skipped; `io.popen` covers it,
  which the PLAN said was acceptable ("add only if clumsy").

## Out of scope (per PLAN)

- **Windows.** The native module is POSIX-only (`dirent.h`, `lstat`, `mkdtemp`, …),
  the Makefile assumes `uname` + a POSIX shell, and `cdeps.lua` shells out to
  `find`/`cp`/`shasum`/etc. with `sh` quoting. A native Windows port is real work
  (a `_WIN32` branch in `cdeps.c`, `-DLUA_USE_WINDOWS`, a Windows-aware `shquote`),
  not a flag flip. MSYS2/Cygwin/Git-Bash + MinGW may work incidentally, untested.
