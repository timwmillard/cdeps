# cdeps — vendored dependency manager

A small CLI that vendors C/C++ dependencies into a project's source tree from a
Lazy.nvim-style Lua config, recording exact pins + file hashes in a lockfile.

## Goal & philosophy

- **Vendored, committed deps (the aim).** After `cdeps` runs, every dependency
  file lives in the repo and is committed. Other developers clone and build with
  **no extra download step** and **no dependency on cdeps**.

Read more about the [design](docs/PLAN.md).

See the [examples](examples/deps.lua) for a real-world use case.
