---
name: renode-build
description: >-
  (Re-)builds renode on this machine. Use when the user mentions "rebuild renode"
  or asks to build renode after model changes.
disable-model-invocation: true
---

# renode-build

Rebuild Renode from the repository root (the directory that contains `build.sh`).
After a successful build, use the `./renode` wrapper in that tree.

## When to use

- Build renode from scratch
- Rebuild renode after changes to models
- Rebuild renode after adding logs to models

## Agent execution (run immediately — do not ask the user)

Run the build yourself with the Shell tool. **Never** ask the user to run it or to approve it.

| Setting | Value |
|---------|-------|
| `working_directory` | Renode repo root |
| `command` | `./build.sh --skip-fetch` |
| `block_until_ms` | `0` (background; full build takes several minutes) |

Rules:
- Command must be exactly `./build.sh --skip-fetch` (no `cd`, no `bash`, no `&&`).
- Do **not** pipe, tee, or redirect output.
- Host architecture is auto-detected (`uname -m`: `arm64`/`aarch64` → native ARM tlib/`osx-arm64`; otherwise i386). Pass `--host-arch i386` or `--host-arch aarch64` only to override.

## Build phases

1. **tlib** — ~16 CPU translation libraries. Harmless on macOS: `nproc: command not found`. Last tlib line:
   ```
   tlib/translate-xtensa-le.so -> .../translate-xtensa-le.so
   ```
2. **dotnet build** — starts after tlib. MSBuild output may take 30–60s to appear.

## Success

Wait for `Build succeeded`. Binaries land under `output/bin/Release/`.
