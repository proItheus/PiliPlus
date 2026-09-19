# Technical Design

## Boundary

This task adds repository tooling and agent documentation only. The runtime path is:

`direnv` → `use nix` → root `shell.nix` → `just` and `fvm` on `PATH` → FVM reads `.fvmrc` → Flutter/Dart commands.

Nix supplies the command-line tools, while FVM remains the sole Flutter SDK selector. Platform SDKs and native libraries remain host responsibilities.

## Files and Responsibilities

- `shell.nix` — import the ambient `<nixpkgs>` set and expose `just` plus `fvm` through `pkgs.mkShell`.
- `.envrc` — contain `use nix` so direnv evaluates the root shell expression.
- `justfile` — define a default recipe that lists commands and recipes for setup, dependencies, formatting, analysis, tests, checks, code generation, JNI generation, running, cleaning, and builds. Every Flutter/Dart invocation is prefixed with `fvm`.
- `.trellis/spec/guides/development-workflow.md` — canonical agent/developer instructions for entering the environment and selecting recipes.
- `.trellis/spec/guides/index.md` — link the new guide from the existing shared guide index.
- `AGENTS.md` — add a short discoverability section outside the Trellis-managed block pointing agents at the canonical guide and primary commands.

## Recipe Contract

The justfile will use these stable entry points:

- `setup` — install the `.fvmrc` SDK and fetch Dart packages.
- `deps` — fetch Dart packages without reinstalling the SDK.
- `format` / `format-check` — format or verify `lib`, `test`, and `tool`.
- `analyze` — run Flutter analysis.
- `test` — run Flutter tests and accept optional test arguments.
- `check` — run format-check, analysis, and tests in sequence.
- `codegen` — run `build_runner` with conflict cleanup.
- `jnigen` — run the repository's `tool/jnigen.dart` entrypoint.
- `run` — start Flutter and accept optional arguments.
- `build` — build a target (APK by default) and accept optional arguments.
- `clean` — run Flutter clean.

The recipes intentionally do not encode platform-specific build flags or native SDK setup.

## Compatibility and Rollback

The shell follows the repository's existing legacy `nix-shell` convention and does not add a flake or pin nixpkgs. This keeps the requested files small but means package versions follow the user's configured nixpkgs channel. If a future reproducibility requirement appears, a pinned flake can replace this boundary without changing the justfile contract.

The change is additive and reversible: remove the new root tooling files and documentation links/sections. No application or generated source needs migration.
