-- cdeps.lua — vendored dependency manager (logic layer)
--
-- This is the "thick" half of cdeps (see docs/PLAN.md). It runs either embedded in
-- the C shell (cdeps.c, which preloads the `cdeps_native` module) or directly
-- under a system `lua` for development. When the native module is absent it
-- falls back to shelling out to coreutils + shasum, so the whole flow is
-- exercisable with plain `lua cdeps.lua <cmd>`.

local M = {}

--==========================================================================--
-- Native primitives: C module if present, else POSIX-shell fallback.
--==========================================================================--

local native = (function()
  local ok, m = pcall(require, "cdeps_native")
  if ok and m then return m end
  return nil
end)()

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- run a command; return ok(boolean), exitcode(number)
local function run(cmd)
  local ok, _, code = os.execute(cmd)
  if ok == true then return true, 0 end
  return false, code or 1
end

-- run capturing stdout; return stdout(string), ok(boolean)
local function capture(cmd)
  local f = io.popen(cmd)
  if not f then return "", false end
  local out = f:read("*a") or ""
  local ok = f:close()
  return out, (ok == true)
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Filesystem helpers (native-backed, shell fallback).
local fs = {}

function fs.exists(p)
  if native then return native.exists(p) end
  return (run("test -e " .. shquote(p)))
end

function fs.isdir(p)
  if native then return native.isdir(p) end
  return (run("test -d " .. shquote(p)))
end

function fs.mkdirp(p)
  if native then return native.mkdirp(p) end
  return (run("mkdir -p " .. shquote(p)))
end

function fs.rmrf(p)
  if native then return native.rmrf(p) end
  return (run("rm -rf " .. shquote(p)))
end

function fs.mkdtemp()
  if native then return native.mkdtemp() end
  local base = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")
  local out, ok = capture("mktemp -d " .. shquote(base .. "/cdeps-XXXXXX"))
  if not ok then return nil end
  return trim(out)
end

-- copy a single file src -> dst, creating dst's parent dir.
function fs.copy_file(src, dst)
  local dir = dst:match("^(.*)/[^/]*$")
  if dir and dir ~= "" then fs.mkdirp(dir) end
  if native then return native.copy_file(src, dst) end
  return (run("cp -p " .. shquote(src) .. " " .. shquote(dst)))
end

-- list regular files under dir as paths relative to dir, excluding any .git.
function fs.walk(dir)
  if native then return native.walk(dir) end
  local out, ok = capture("cd " .. shquote(dir) ..
    " && find . -type f -not -path './.git/*' 2>/dev/null")
  if not ok then return {} end
  local files = {}
  for line in out:gmatch("[^\n]+") do
    local rel = line:gsub("^%./", "")
    if rel ~= "" then files[#files + 1] = rel end
  end
  table.sort(files)
  return files
end

function fs.sha256(path)
  if native then return native.sha256(path) end
  local out, ok = capture("shasum -a 256 " .. shquote(path) .. " 2>/dev/null")
  if not ok then return nil end
  return out:match("^(%x+)")
end

function fs.sha256_string(s)
  if native then return native.sha256_string(s) end
  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  if not f then return nil end
  f:write(s); f:close()
  local h = fs.sha256(tmp)
  os.remove(tmp)
  return h
end

--==========================================================================--
-- Small utilities
--==========================================================================--

local function basename(p) return (p:gsub("/+$", ""):match("[^/]+$")) or p end
local function dirname(p) return (p:match("^(.*)/[^/]+/?$")) or "." end
local function join(a, b)
  if a == "" or a == "." then return b end
  return a:gsub("/+$", "") .. "/" .. b
end

local function die(fmt, ...)
  io.stderr:write("cdeps: " .. string.format(fmt, ...) .. "\n")
  os.exit(1)
end

local function warn(fmt, ...)
  io.stderr:write("cdeps: warning: " .. string.format(fmt, ...) .. "\n")
end

local function info(fmt, ...)
  io.write(string.format(fmt, ...) .. "\n")
end

local function confirm(prompt)
  if os.getenv("CDEPS_YES") or M._yes then return true end
  io.write(prompt .. " [y/N] ")
  io.flush()
  local ans = io.read("*l")
  return ans and (ans:lower() == "y" or ans:lower() == "yes")
end

-- glob -> Lua anchored pattern. Supports ** (any, incl. /), * (no /), ?.
local function glob_to_pat(glob)
  local p = glob:gsub("[%(%)%.%%%+%-%[%]%^%$]", "%%%0")
  p = p:gsub("%*%*", "\1")
  p = p:gsub("%*", "[^/]*")
  p = p:gsub("\1", ".*")
  p = p:gsub("%?", "[^/]")
  return "^" .. p .. "$"
end

local function glob_match(pattern, path)
  return path:match(glob_to_pat(pattern)) ~= nil
end

--==========================================================================--
-- Cache & config locations
--==========================================================================--

local HOME = os.getenv("HOME") or "."
local CACHE_ROOT = (os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")) .. "/cdeps"

local function cache_git_dir(host, path)
  return join(join(CACHE_ROOT, "git"), join(host, path))
end

-- djb2 hash -> hex, used to name cached downloads from their URL.
local function strhash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

--==========================================================================--
-- Spec parsing / normalization
--==========================================================================--

local ARCHIVE_EXTS = { "%.tar%.gz$", "%.tgz$", "%.tar%.bz2$", "%.tar$", "%.zip$" }

local function is_archive_url(url)
  for _, pat in ipairs(ARCHIVE_EXTS) do
    if url:match(pat) then return true end
  end
  return false
end

-- Resolve [1]/url shorthand into a concrete URL + transport + name.
local function resolve_source(spec)
  local one = spec[1]
  local url = spec.url
  local is_shorthand = false
  if not url and one then
    if one:match("^https?://") or one:match("^git@") then
      url = one
    elseif one:find("/") then
      url = "https://github.com/" .. one .. ".git"
      is_shorthand = true
    else
      die("spec '%s' is not a user/repo or url", tostring(one))
    end
  end
  if not url then die("spec missing both [1] and url") end

  local transport
  if url:match("%.git$") or url:match("^git@") or is_shorthand then
    transport = "git"
  elseif is_archive_url(url) then
    transport = "archive"
  else
    transport = "file"
  end

  -- name: repo for git, filename-stem otherwise.
  local name = spec.name
  if not name then
    if transport == "git" then
      name = basename(url):gsub("%.git$", "")
    else
      name = basename(url)
      name = name:gsub("%.tar%.gz$", ""):gsub("%.tgz$", ""):gsub("%.tar%.bz2$", "")
                 :gsub("%.tar$", ""):gsub("%.zip$", ""):gsub("%.%w+$", "")
    end
  end

  return url, transport, name
end

-- Parse a git URL into (host, "user/repo") for cache layout.
local function parse_git_url(url)
  local host, path = url:match("^git@([^:]+):(.+)$")
  if not host then
    host, path = url:match("^https?://([^/]+)/(.+)$")
  end
  if not host then host, path = "local", url:gsub("[^%w]", "_") end
  path = path:gsub("%.git$", "")
  return host, path
end

local function normalize(spec, cfg)
  local url, transport, name = resolve_source(spec)
  local dir = (cfg and cfg.dir) or "."
  local has_files = spec.files ~= nil and #spec.files > 0

  local dest = spec.dest
  if not dest then
    if has_files or transport ~= "git" then
      dest = dir            -- flat
    else
      dest = join(dir, name) -- whole-repo tree
    end
  end

  -- A git repo vendored without a `files` filter owns its whole (dedicated)
  -- dest dir. The commit already pins every file's content, so the lock records
  -- one tree digest for `verify` instead of a per-file hash list.
  local whole_tree = (transport == "git") and not has_files

  return {
    name = name,
    url = url,
    transport = transport,
    files = spec.files,
    whole_tree = whole_tree,
    dest = dest,
    flatten = (spec.flatten ~= false),
    strip_prefix = spec.strip_prefix,
    submodules = (spec.submodules ~= false),
    branch = spec.branch,
    tag = spec.tag,
    commit = spec.commit,
    version = spec.version,
    build = spec.build,
    raw = spec,
  }
end

-- Is the pin immutable/explicit (commit/tag/version) vs floating?
local function is_pinned(s)
  return s.commit ~= nil or s.tag ~= nil or s.version ~= nil
end

-- Compare two glob lists as order-independent sets (nil == empty). Used by sync
-- to notice when deps.lua's `files` filter changed since the lock was written.
local function same_globs(a, b)
  a, b = a or {}, b or {}
  if #a ~= #b then return false end
  local set = {}
  for _, g in ipairs(a) do set[g] = (set[g] or 0) + 1 end
  for _, g in ipairs(b) do
    if not set[g] then return false end
    set[g] = set[g] - 1
    if set[g] == 0 then set[g] = nil end
  end
  return next(set) == nil
end

--==========================================================================--
-- semver (minimal): pick newest tag, or exact / "latest".
--==========================================================================--

local function parse_semver(tag)
  local v = tag:gsub("^v", "")
  local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) or 0, tag = tag }
end

local function semver_lt(x, y)
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] < y[i] end
  end
  return false
end

local function resolve_version(tags, version)
  local parsed = {}
  for _, t in ipairs(tags) do
    local pv = parse_semver(t)
    if pv then parsed[#parsed + 1] = pv end
  end
  table.sort(parsed, semver_lt)
  if version == "latest" then
    return parsed[#parsed] and parsed[#parsed].tag
  end
  for _, pv in ipairs(parsed) do
    if pv.tag == version or pv.tag == "v" .. version or pv.tag:gsub("^v", "") == version then
      return pv.tag
    end
  end
  return nil
end

--==========================================================================--
-- git transport
--==========================================================================--

local function git(cachedir, args)
  return capture("git -C " .. shquote(cachedir) .. " " .. args .. " 2>/dev/null")
end

local function git_ensure_clone(s)
  local host, path = parse_git_url(s.url)
  local cachedir = cache_git_dir(host, path)
  if not fs.isdir(join(cachedir, ".git")) then
    fs.mkdirp(dirname(cachedir))
    info("  cloning %s", s.url)
    local ok = run("git clone --filter=blob:none --also-filter-submodules" ..
      " --recurse-submodules" ..
      " -c core.autocrlf=false " .. shquote(s.url) .. " " .. shquote(cachedir))
    if not ok then die("clone failed: %s", s.url) end
  end
  return cachedir
end

local function git_default_branch(cachedir)
  local out = trim(git(cachedir, "symbolic-ref --short refs/remotes/origin/HEAD") or "")
  if out == "" then
    run("git -C " .. shquote(cachedir) .. " remote set-head origin -a >/dev/null 2>&1")
    out = trim(git(cachedir, "symbolic-ref --short refs/remotes/origin/HEAD") or "")
  end
  return (out:gsub("^origin/", ""))
end

-- Returns resolved commit and the tracked branch (for the lock's intent field).
local function git_resolve(s, cachedir, do_fetch)
  if do_fetch then
    run("git -C " .. shquote(cachedir) .. " fetch --filter=blob:none --tags --prune origin >/dev/null 2>&1")
  end
  local branch = s.branch
  local commit

  if s.commit then
    commit = s.commit
  elseif s.tag then
    commit = trim(git(cachedir, "rev-list -n1 " .. shquote(s.tag)) or "")
    if commit == "" then die("%s: tag not found: %s", s.name, s.tag) end
  elseif s.version then
    local out = git(cachedir, "tag --list") or ""
    local tags = {}
    for t in out:gmatch("[^\n]+") do tags[#tags + 1] = trim(t) end
    local tag = resolve_version(tags, s.version)
    if not tag then die("%s: no tag matches version %s", s.name, s.version) end
    commit = trim(git(cachedir, "rev-list -n1 " .. shquote(tag)) or "")
  elseif s.branch then
    commit = trim(git(cachedir, "rev-parse " .. shquote("origin/" .. s.branch)) or "")
    if commit == "" then die("%s: branch not found: %s", s.name, s.branch) end
  else
    branch = git_default_branch(cachedir)
    commit = trim(git(cachedir, "rev-parse " .. shquote("origin/" .. branch)) or "")
    if commit == "" then
      commit = trim(git(cachedir, "rev-parse origin/HEAD") or "")
    end
  end

  if not commit or #commit < 7 then die("%s: could not resolve a commit", s.name) end
  return commit, branch
end

-- Check out `commit` into the cache working tree (+ submodules); return the
-- cache dir as the staging root to copy filtered files from.
local function git_checkout(s, cachedir, commit)
  local ok = run("git -C " .. shquote(cachedir) .. " checkout -f " .. shquote(commit) .. " >/dev/null 2>&1")
  if not ok then die("%s: checkout %s failed", s.name, commit:sub(1, 12)) end
  if s.submodules then
    run("git -C " .. shquote(cachedir) .. " submodule update --init --recursive --filter=blob:none >/dev/null 2>&1")
  end
  return cachedir
end

--==========================================================================--
-- archive / file transport
--==========================================================================--

local function download(url)
  fs.mkdirp(join(CACHE_ROOT, "dl"))
  local dl = join(join(CACHE_ROOT, "dl"), strhash(url) .. "-" .. basename(url))
  if not fs.exists(dl) then
    info("  downloading %s", url)
    local ok = run("curl -fsSL " .. shquote(url) .. " -o " .. shquote(dl))
    if not ok then
      fs.rmrf(dl)
      die("download failed: %s", url)
    end
  end
  return dl
end

local function extract_archive(dl, url)
  local staging = fs.mkdtemp()
  if not staging then die("could not create staging dir") end
  local ok
  if url:match("%.zip$") then
    ok = run("unzip -q -o " .. shquote(dl) .. " -d " .. shquote(staging))
  else
    ok = run("tar -xf " .. shquote(dl) .. " -C " .. shquote(staging))
  end
  if not ok then die("extraction failed: %s", url) end
  return staging
end

-- Strip an explicit or auto-detected single leading directory.
local function apply_strip(root, strip_prefix)
  if strip_prefix then
    return join(root, strip_prefix)
  end
  local out = capture("ls -1 " .. shquote(root) .. " 2>/dev/null") or ""
  local entries = {}
  for e in out:gmatch("[^\n]+") do entries[#entries + 1] = e end
  if #entries == 1 and fs.isdir(join(root, entries[1])) then
    return join(root, entries[1])
  end
  return root
end

--==========================================================================--
-- Vendoring: compute outputs, detect collisions, copy, hash.
--==========================================================================--

-- Returns ordered list of { target=<dest path>, src=<staging path>, rel=<rel> }.
local function plan_outputs(s, root)
  local outputs, seen = {}, {}
  local all = fs.walk(root)
  local has_files = s.files and #s.files > 0
  local function add(rel)
    if seen[rel] then return end
    seen[rel] = true
    -- flatten only applies when picking loose files; a whole-tree vendor (no
    -- `files`) always mirrors the tree, else nested files collide on basename.
    local out = (has_files and s.flatten) and basename(rel) or rel
    outputs[#outputs + 1] = { target = join(s.dest, out), src = join(root, rel), rel = rel }
  end
  if has_files then
    for _, pat in ipairs(s.files) do
      for _, rel in ipairs(all) do
        if glob_match(pat, rel) then add(rel) end
      end
    end
  else
    for _, rel in ipairs(all) do add(rel) end
  end
  table.sort(outputs, function(a, b) return a.target < b.target end)
  return outputs
end

-- copy outputs into dest, registering ownership + detecting cross-dep collisions.
local function copy_outputs(s, outputs, owned)
  for _, o in ipairs(outputs) do
    if owned[o.target] and owned[o.target] ~= s.name then
      die("%s: file collision at %s (also owned by %s) — set a per-dep dest",
        s.name, o.target, owned[o.target])
    end
    owned[o.target] = s.name
    local ok = fs.copy_file(o.src, o.target)
    if not ok then die("%s: copy failed: %s -> %s", s.name, o.src, o.target) end
  end
end

-- sorted lock file-list {path, sha256} for the copied outputs.
local function hash_outputs(outputs)
  local files = {}
  for _, o in ipairs(outputs) do
    files[#files + 1] = { path = o.target, sha256 = fs.sha256(o.target) }
  end
  table.sort(files, function(a, b) return a.path < b.path end)
  return files
end

-- Go h1-style dirhash: one sha256 over the sorted "<sha256>  <relpath>" lines of
-- every file under dir (.git already excluded by fs.walk). Self-contained — no
-- git needed to recompute — so a single digest stands in for a per-file list
-- when a dep owns its entire dest tree.
local function tree_digest(dir)
  local lines = {}
  for _, rel in ipairs(fs.walk(dir)) do
    local h = fs.sha256(join(dir, rel))
    if not h then return nil end
    lines[#lines + 1] = h .. "  " .. rel
  end
  table.sort(lines)
  return fs.sha256_string(table.concat(lines, "\n") .. "\n")
end

-- Run the author-written build hook (after fetch, before hashing).
local function run_build_hook(s, root)
  if not s.build then return end
  local ctx = {
    src = root,
    dest = s.dest,
    run = function(cmd) return run("cd " .. shquote(root) .. " && " .. cmd) end,
    copy = function(rel, to) return fs.copy_file(join(root, rel), to or join(s.dest, basename(rel))) end,
  }
  s.build(ctx)
end

-- Fetch + vendor a single normalized spec. Returns its lock entry.
-- `do_fetch` controls whether floating refs are revalidated.
local function acquire(s, owned, do_fetch)
  info("%s", s.name)
  local entry = { url = s.url, dest = s.dest }
  local root

  if s.transport == "git" then
    local cachedir = git_ensure_clone(s)
    local need_fetch = do_fetch or s.commit == nil
    local commit, branch = git_resolve(s, cachedir, need_fetch)
    root = git_checkout(s, cachedir, commit)
    entry.commit = commit
    entry.branch = branch
  elseif s.transport == "archive" then
    local dl = download(s.url)
    entry.archive_sha256 = fs.sha256(dl)
    local extracted = extract_archive(dl, s.url)
    root = apply_strip(extracted, s.strip_prefix)
    M._cleanup[#M._cleanup + 1] = extracted
  else -- file
    local dl = download(s.url)
    root = fs.mkdtemp()
    M._cleanup[#M._cleanup + 1] = root
    fs.copy_file(dl, join(root, basename(s.url)))
  end

  run_build_hook(s, root)

  local outputs = plan_outputs(s, root)
  copy_outputs(s, outputs, owned)
  if s.whole_tree then
    -- whole-repo vendor: the commit pins content, the dest dir is owned
    -- wholesale, so one tree digest replaces the per-file list.
    entry.tree_sha256 = tree_digest(s.dest)
  else
    entry.files = hash_outputs(outputs)
    -- remember the requested glob filter so sync can tell when deps.lua adds or
    -- drops a `files` entry and re-fetch instead of assuming "present".
    if s.files and #s.files > 0 then entry.spec_files = s.files end
  end
  return entry
end

--==========================================================================--
-- Lockfile serialization
--==========================================================================--

local function serialize_value(v, indent)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    return M._serialize_table(v, indent)
  end
  return "nil"
end

function M._serialize_table(tbl, indent)
  indent = indent or ""
  local ni = indent .. "  "
  local parts = {}
  local n = #tbl
  for i = 1, n do
    parts[#parts + 1] = ni .. serialize_value(tbl[i], ni) .. ","
  end
  local keys = {}
  for k in pairs(tbl) do
    if type(k) == "string" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    -- dep names become lock keys; repo names often contain '-' etc, so quote
    -- anything that isn't a bare Lua identifier (e.g. ["Hello-World"] = ...).
    local key = k:match("^[%a_][%w_]*$") and k or string.format("[%q]", k)
    parts[#parts + 1] = string.format("%s%s = %s,", ni, key, serialize_value(tbl[k], ni))
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end

local function write_lock(lock)
  lock.lockfile_version = 1
  local body = "-- deps.lock — generated by cdeps. Do not edit by hand.\nreturn " ..
    M._serialize_table(lock, "") .. "\n"
  local f = assert(io.open("deps.lock", "w"))
  f:write(body)
  f:close()
end

local function read_lock()
  if not fs.exists("deps.lock") then return nil end
  local chunk = assert(loadfile("deps.lock"))
  return chunk()
end

local function read_config()
  if not fs.exists("deps.lua") then die("no deps.lua in current directory") end
  local chunk = assert(loadfile("deps.lua"))
  local t = chunk()
  if type(t) ~= "table" then die("deps.lua must return a table") end
  return t
end

-- Load deps.lua and return (cfg, list of normalized specs).
local function load_specs()
  local t = read_config()
  local cfg = t.config or {}
  local specs = {}
  for _, raw in ipairs(t) do
    specs[#specs + 1] = normalize(raw, cfg)
  end
  return cfg, specs
end

--==========================================================================--
-- Gitignore nudge (PLAN: warn if dest is ignored — likely accidental).
--==========================================================================--

local function check_gitignore(specs)
  if not fs.isdir(".git") then return end
  local seen = {}
  for _, s in ipairs(specs) do
    local dir = s.dest
    if not seen[dir] then
      seen[dir] = true
      local out = capture("git check-ignore " .. shquote(dir) .. " 2>/dev/null") or ""
      if trim(out) ~= "" then
        warn("'%s' is gitignored — vendored files won't be committed (fetch-mode); silence by un-ignoring it.", dir)
      end
    end
  end
end

--==========================================================================--
-- Commands
--==========================================================================--

M._cleanup = {}

local function cleanup()
  for _, d in ipairs(M._cleanup) do fs.rmrf(d) end
  M._cleanup = {}
end

-- bare / install: vendor anything missing; reuse lock pins when present.
function M.sync()
  local cfg, specs = load_specs()
  check_gitignore(specs)
  local lock = read_lock() or {}
  local owned = {}
  local newlock = { lockfile_version = 1 }

  for _, s in ipairs(specs) do
    local le = lock[s.name]
    -- present = vendored files already on disk (existence only, like file deps;
    -- drift detection is `verify`'s job, not sync's).
    local all_present = false
    if le and le.tree_sha256 then
      all_present = fs.isdir(le.dest) and #fs.walk(le.dest) > 0
    elseif le and le.files and #le.files > 0 then
      all_present = true
      for _, f in ipairs(le.files) do
        if not fs.exists(f.path) then all_present = false break end
      end
      -- the lock's file list is only valid for the glob filter it was built from;
      -- if deps.lua's `files` changed, re-fetch so added globs get vendored.
      if all_present and not same_globs(le.spec_files, s.files) then
        all_present = false
      end
    end
    if all_present then
      info("%s (present)", s.name)
      if le.tree_sha256 then
        for _, rel in ipairs(fs.walk(le.dest)) do owned[join(le.dest, rel)] = s.name end
      else
        for _, f in ipairs(le.files) do owned[f.path] = s.name end
      end
      newlock[s.name] = le
    else
      -- reuse pinned commit from lock for reproducibility (floating deps only)
      if le and le.commit and not is_pinned(s) and not s.branch then
        s.commit = le.commit
      end
      newlock[s.name] = acquire(s, owned, false)
    end
  end

  write_lock(newlock)
  cleanup()
  info("done — %d deps, lock written", #specs)
end

function M.verify()
  local _, specs = load_specs()
  local lock = read_lock()
  if not lock then die("no deps.lock — run cdeps first") end
  local bad = 0
  for _, s in ipairs(specs) do
    local le = lock[s.name]
    if not le then
      warn("%s: no lock entry", s.name); bad = bad + 1
    elseif le.tree_sha256 then
      if not fs.isdir(le.dest) then
        warn("%s: missing tree %s", s.name, le.dest); bad = bad + 1
      elseif tree_digest(le.dest) ~= le.tree_sha256 then
        warn("%s: tree hash mismatch %s", s.name, le.dest); bad = bad + 1
      end
    else
      for _, f in ipairs(le.files or {}) do
        if not fs.exists(f.path) then
          warn("%s: missing %s", s.name, f.path); bad = bad + 1
        else
          local h = fs.sha256(f.path)
          if h ~= f.sha256 then
            warn("%s: hash mismatch %s", s.name, f.path); bad = bad + 1
          end
        end
      end
    end
  end
  if bad > 0 then die("verify failed: %d problem(s)", bad) end
  info("verify ok")
end

function M.update(name)
  local _, specs = load_specs()
  local lock = read_lock() or {}
  local newlock = { lockfile_version = 1 }
  local owned = {}

  for _, s in ipairs(specs) do newlock[s.name] = lock[s.name] end

  for _, s in ipairs(specs) do
    if name and s.name ~= name then goto continue end
    local le = lock[s.name]

    if s.transport == "git" then
      local cachedir = git_ensure_clone(s)
      local commit = git_resolve(s, cachedir, true)
      if le and le.commit == commit then
        info("%s up to date (%s)", s.name, commit:sub(1, 12))
        goto continue
      end
      if le and is_pinned(s) and le.commit ~= commit then
        warn("%s: pinned ref now resolves to a DIFFERENT commit", s.name)
        warn("  lock: %s  now: %s", tostring(le.commit), commit)
        if not confirm("Accept the new commit? (tag may have been force-moved)") then
          die("aborted: pinned ref changed")
        end
      end
      if le and le.commit then
        info("%s: %s -> %s", s.name, le.commit:sub(1, 12), commit:sub(1, 12))
        if not is_pinned(s) and not confirm("Update floating dep " .. s.name .. "?") then
          info("  skipped"); goto continue
        end
      end
    end

    newlock[s.name] = acquire(s, owned, true)
    ::continue::
  end

  write_lock(newlock)
  cleanup()
  info("update done")
end

function M.remove(name)
  if not name then die("usage: cdeps remove <name>") end
  local lock = read_lock() or {}
  local le = lock[name]
  if not le then die("no such dep in lock: %s", name) end
  if le.tree_sha256 then
    fs.rmrf(le.dest)
    info("  removed %s", le.dest)
  else
    for _, f in ipairs(le.files or {}) do
      fs.rmrf(f.path)
      info("  removed %s", f.path)
    end
  end
  lock[name] = nil
  write_lock(lock)
  warn("removed '%s' from deps.lock + vendored files; edit deps.lua to drop the spec.", name)
end

function M.tidy()
  local _, specs = load_specs()
  local lock = read_lock() or {}
  local in_lua = {}
  for _, s in ipairs(specs) do in_lua[s.name] = true end

  for lname, le in pairs(lock) do
    if lname ~= "lockfile_version" and not in_lua[lname] then
      info("dropping stale dep '%s'", lname)
      if le.tree_sha256 then
        fs.rmrf(le.dest); info("  removed %s", le.dest)
      else
        for _, f in ipairs(le.files or {}) do
          fs.rmrf(f.path); info("  removed %s", f.path)
        end
      end
      lock[lname] = nil
    end
  end
  write_lock(lock)

  local owned = {}
  for lname, le in pairs(lock) do
    if lname ~= "lockfile_version" then
      if le.tree_sha256 then
        for _, rel in ipairs(fs.walk(le.dest)) do owned[join(le.dest, rel)] = true end
      else
        for _, f in ipairs(le.files or {}) do owned[f.path] = true end
      end
    end
  end
  local destdirs = {}
  for _, s in ipairs(specs) do destdirs[s.dest] = true end
  for d in pairs(destdirs) do
    if fs.isdir(d) then
      for _, rel in ipairs(fs.walk(d)) do
        local p = join(d, rel)
        if not owned[p] then
          warn("unowned file in %s: %s (not deleting)", d, p)
        end
      end
    end
  end
  info("tidy done")
end

-- add: scaffold a spec into deps.lua, then vendor it.
function M.add(arg)
  if not arg then die("usage: cdeps add <user/repo|url>") end
  if not fs.exists("deps.lua") then
    local f = assert(io.open("deps.lua", "w"))
    f:write("return {\n}\n")
    f:close()
  end
  local src = assert(io.open("deps.lua", "r")):read("*a")
  local entry = string.format('  { %q },\n', arg)
  local newsrc, n = src:gsub("(\n}%s*)$", "\n" .. entry .. "}\n", 1)
  if n == 0 then die("could not edit deps.lua automatically; add the spec by hand") end
  local f = assert(io.open("deps.lua", "w"))
  f:write(newsrc)
  f:close()
  info("added %q to deps.lua", arg)
  M.sync()
end

--==========================================================================--
-- Entry point
--==========================================================================--

function M.main(argv)
  argv = argv or {}
  local args = {}
  for _, a in ipairs(argv) do
    if a == "-y" or a == "--yes" then M._yes = true else args[#args + 1] = a end
  end

  local cmd = args[1]
  if not cmd or cmd == "install" or cmd == "sync" then
    M.sync()
  elseif cmd == "verify" then
    M.verify()
  elseif cmd == "update" then
    M.update(args[2])
  elseif cmd == "remove" then
    M.remove(args[2])
  elseif cmd == "tidy" then
    M.tidy()
  elseif cmd == "add" then
    M.add(args[2])
  elseif cmd == "help" or cmd == "-h" or cmd == "--help" then
    io.write([[
cdeps — vendored dependency manager

  cdeps [install|sync]      vendor anything in deps.lua missing from the tree
  cdeps add <user/repo|url> scaffold a spec, vendor it, update the lock
  cdeps update [name]       re-resolve refs, re-fetch, re-hash, rewrite lock
  cdeps verify              re-hash deps/ against the lock (CI gate)
  cdeps remove <name>       delete owned files + drop from the lock
  cdeps tidy                reconcile deps.lua <-> lock <-> deps/
  -y, --yes                 assume yes for update confirmations
]])
  else
    die("unknown command: %s (try 'cdeps help')", cmd)
  end
end

-- Run as the main chunk: both the system-lua dev path (`lua cdeps.lua …`) and
-- the embedded C shell (cdeps.c) populate the standard `arg` table and run this
-- file as the program, so dispatching on `arg` works the same either way.
M.main(arg)

return M
