-- cdeps' own dependencies — cdeps manages cdeps (dogfood, see PLAN.md).
--
-- The only dependency is the Lua runtime cdeps embeds. It was first vendored by
-- hand (the bootstrap), and is now an ordinary entry: `cdeps update` follows new
-- releases, and `rm -rf deps && cdeps` restores it from deps.lock. The built
-- binary embeds its own Lua, so deps/lua-5.5.0 is only a *build* input — cdeps
-- can repopulate the very dir that held its own Lua source.
return {
  -- Official lua.org amalgam (not the lua/lua git mirror): the archive's single
  -- top dir is auto-stripped, then the whole tree is vendored to deps/lua-5.5.0
  -- so the Makefile's -Ideps/lua-5.5.0/src path stays put.
  { url = "https://www.lua.org/ftp/lua-5.5.0.tar.gz",
    name = "lua", dest = "deps/lua-5.5.0" },
}
