-- Example cdeps config — a port of ~/cprogs/singlefile_libs/Makefile.
--
-- cdeps replaces that Makefile: instead of hand-written `wget -O deps/x.h <url>`
-- rules, you declare deps here and run `cdeps`. The `config` block below sets
-- `dir = "deps"` so everything lands flat in deps/, exactly like the Makefile.
--
-- Notes vs. the Makefile:
--   * Branch is auto-detected from the repo's default (master/main), so unlike
--     the Makefile you don't hardcode `refs/heads/master` per URL.
--   * github "user/repo" is the default host; gitlab/others use an explicit url.
--   * Release assets & archives aren't in the git tree, so they use a direct url
--     (file/archive transport) rather than the clone+filter shorthand.
--   * See NOTES at the bottom for the single-file-clone-cost tradeoff.

return {

  -- Optional global config (the `config` key; array entries below are the specs).
  -- `dir` is the base directory all default dest paths are built against. It
  -- defaults to "." (the current dir); set it to e.g. "deps", "vendor", or
  -- "third_party" to relocate everything. Per-entry `dest` still overrides.
  config = { dir = "deps" },

  ---------------------------------------------------------------- Graphics / UI
  -- multi-file repos: cloning + filtering earns its keep here
  { "floooh/sokol", files = {
      "sokol_app.h", "sokol_audio.h", "sokol_gfx.h", "sokol_glue.h",
      "sokol_time.h", "sokol_log.h", "sokol_fetch.h",
  } },

  { "edubart/sokol_gp", files = { "sokol_gp.h" } },

  -- nuklear: a group spanning two repos -> two entries (both land flat in deps/)
  { "Immediate-Mode-UI/Nuklear", files = { "nuklear.h" } },
  { "floooh/sokol",              files = { "util/sokol_nuklear.h" } },  -- subpath -> deps/sokol_nuklear.h

  -- clay: clay.h + its sokol renderer (same repo, different paths) + fontstash
  { "nicbarker/clay", files = { "clay.h", "renderers/sokol/sokol_clay.h" } },
  { "floooh/sokol",   files = { "util/sokol_fontstash.h" } },

  -- Dear ImGui via cimgui + sokol glue.
  --   * sokol_imgui.h -> deps/   (the sokol+imgui glue header)
  --   * cimgui (C API) + its Dear ImGui submodule, cloned together -> deps/cimgui/
  -- cimgui vendors Dear ImGui as a git submodule at imgui/, pinned by cimgui's
  -- `docking_inter` branch to a specific imgui commit. `submodules = true` makes
  -- the recursive clone materialize that exact imgui, so imgui always matches what
  -- cimgui expects — no separate imgui pin to keep in sync (when cimgui bumps the
  -- submodule, `cdeps update` follows). `flatten = false` preserves the imgui/
  -- subpath -> deps/cimgui/imgui/*.
  -- (Alternative: pin ocornut/imgui yourself as a separate `commit =` entry if you
  --  want to control imgui's version independently of cimgui.)
  { "floooh/sokol", files = { "util/sokol_imgui.h" } },

  { "cimgui/cimgui", branch = "docking_inter", submodules = true,
    dest = "deps/cimgui", flatten = false,
    files = {
      "cimconfig.h", "cimgui.h", "cimgui.cpp",
      "imgui/imconfig.h", "imgui/imgui.h", "imgui/imgui.cpp", "imgui/imgui_demo.cpp",
      "imgui/imgui_draw.cpp", "imgui/imgui_internal.h", "imgui/imgui_tables.cpp",
      "imgui/imgui_widgets.cpp", "imgui/imstb_rectpack.h", "imgui/imstb_textedit.h",
      "imgui/imstb_truetype.h",
    } },

  -- ColleagueRiley stack ("riely" target)
  { "ColleagueRiley/RGFW",      files = { "RGFW.h" } },
  { "ColleagueRiley/RSGL",      files = { "RSGL.h" } },
  { "ColleagueRiley/RFont",     files = { "RFont.h" } },
  { "ColleagueRiley/Silicon-h", files = { "silicon.h" } },

  { "nakst/luigi", files = { "experimental/luigi3.h" } },  -- -> deps/luigi3.h

  ---------------------------------------------------------------------- Audio
  { "mackron/miniaudio", files = { "miniaudio.h" } },

  ------------------------------------------------------------ Data / parsing
  { "nothings/stb", files = {
      "stb_ds.h", "stb_image.h", "stb_truetype.h", "stb_image_write.h",
      "stb_image_resize2.h", "stb_perlin.h", "stb_tilemap_editor.h",
      "stb_textedit.h",
  } },

  { "sheredom/json.h", files = { "json.h" } },
  { "zserge/jsmn",     files = { "jsmn.h" } },
  { "tspader/toml",    files = { "toml.h" } },

  -- gitlab source (explicit url overrides the github default).
  { url = "https://gitlab.com/bztsrc/jsonc.git", files = { "jsonc.c" } },

  -- RandyGaul/cute_headers provides several single headers across categories
  { "RandyGaul/cute_headers", files = { "cute_tiled.h", "cute_tls.h" } },

  ----------------------------------------------------------------- Utility
  { "tsoding/arena",  files = { "arena.h" } },
  { "tsoding/nob.h",  files = { "nob.h" } },
  { "tsoding/flag.h", files = { "flag.h" } },
  { "edubart/minicoro", files = { "minicoro.h" } },
  { "edubart/minilua",  files = { "minilua.h" } },
  { "RandyGaul/ckit.h", files = { "ckit.h" } },

  { "smcameron/open-simplex-noise-in-c",
    files = { "open-simplex-noise.c", "open-simplex-noise.h" } },

  -- uuid: two separate upstreams
  { "wc-duck/uuid_h",  files = { "uuid.h" } },
  { "LiosK/uuidv7-h",  files = { "uuidv7.h" } },  -- default branch is `main`, auto-detected

  -- sp toolkit: root header + a sp/ subdir of headers (flattened into deps/)
  { "tspader/sp", files = {
      "sp.h", "sp/sp_asset.h", "sp/sp_elf.h", "sp/sp_glob.h",
      "sp/sp_macho.h", "sp/sp_math.h", "sp/sp_msvc.h", "sp/sp_prompt.h",
  } },

  -- "mate" build-system header goes to the project root, not deps/
  { "TomasBorquez/mate.h", files = { "mate.h" }, dest = "." },

  ---------------------------------------------------------------- Networking
  { "erkkah/naett",            files = { "naett.h", "naett.c" } },
  { "cesanta/mongoose",        files = { "mongoose.h", "mongoose.c" } },
  { "mattiasgustavsson/libs",  files = { "http.h" } },

  -- release asset: a single .c published on a GitHub release (not in the tree)
  { url = "https://github.com/OUIsolutions/BearHttpsClient/releases/download/0.2.8/BearHttpsClientOne.c" },

  ------------------------------------------------------------------ Database
  -- sqlite amalgamation zip: extract + flatten the wrapper dir into deps/
  { url = "https://sqlite.org/2025/sqlite-amalgamation-3500400.zip",
    files = { "sqlite3.c", "sqlite3.h" } },   -- auto-strip the single top-level dir

  -- quickjs amalgamation published as a release zip
  { url = "https://github.com/quickjs-ng/quickjs/releases/download/v0.13.0/quickjs-amalgam.zip" },

  ------------------------------------------------------------------- Testing
  { "savashn/myassert", files = { "myassert.h" } },

  ----------------------------------------------- Full C libraries (source trees)
  -- Unlike the single-header libs above, these are whole libraries you compile, so
  -- vendor the ENTIRE repo (no `files` filter): the build files come along too and
  -- a few unused source files don't hurt. With no `files`, dest defaults to
  -- deps/<repo> (the whole tree is mirrored there) — so no explicit dest needed.
  -- If the repo ships a CMakeLists.txt (e.g. raylib), just
  -- `add_subdirectory(deps/raylib)` from your main CMake; Lua is a handful of .c
  -- you add directly. Pinned to release tags (reproducible).
  { "raysan5/raylib", tag = "5.5" },     -- -> deps/raylib/...
  { "lua/lua",        tag = "v5.4.7" },  -- -> deps/lua/...
}

--[[ NOTES — gaps this catalog surfaces in the current schema --------------------

1. Single-file-from-a-repo cost. Many entries above grab ONE header but, via the
   git transport, clone the whole repo to do it. In practice this is cheap and is
   the intended path: blobless clones (`--filter=blob:none`) only pull checked-out
   blobs, multiple files from one repo share a single clone, and the `~/.cache/cdeps`
   cache makes it a one-time cost per repo (updates are delta fetches).
   Clone also keeps host-agnostic behavior, glob support in `files`, and free
   ref->commit pinning — none of which a raw-URL fetch gives without reimplementing
   GitHub API resolution. So there's no auto-switch to raw URLs when `files` is set.
   If you genuinely want zero clone for a specific dep, use an explicit raw `url`
   (file transport) — an opt-in, not implicit behavior.

2. Floating vs pinned refs. Most entries track the default branch (floating) like
   the Makefile — `cdeps update` re-fetches latest. cimgui floats on a non-default
   `branch` (`docking_inter`). Add `tag`/`commit`/`version` to hold any entry
   steady (an exact `commit` makes `update` a no-op until you change the pin).

3. Submodules. cimgui pulls Dear ImGui via `submodules = true`, so the imgui
   version is dictated by cimgui's submodule pointer rather than a pin of our own.
   The lock records cimgui's commit; the vendored imgui files are captured by their
   per-file hashes (and optionally the submodule commit, for provenance).

4. Whole-repo deps. raylib and Lua omit `files` to vendor the entire repo, so build
   files (CMakeLists.txt, makefile) come along. Consume a CMake repo via
   `add_subdirectory(deps/raylib)`; for Lua just compile its .c files.
--]]
