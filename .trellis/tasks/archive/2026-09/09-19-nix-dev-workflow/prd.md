# Add Nix-managed development workflow

## Goal

Provide shell.nix, direnv, just recipes, and agent-facing development guides for the Flutter project.

## Background

- This repository is a Flutter application pinned to Flutter `3.47.4` by both `.fvmrc` and `pubspec.yaml`.
- The repository currently has no checked-in `shell.nix`, `.envrc`, or `justfile`.
- The project already uses `.trellis/spec/guides/` as the shared location for agent-consulted guidance.

## Requirements

- **R1 — Nix shell:** Add a root `shell.nix` that exposes the Nixpkgs `just` and `fvm` packages in the development shell. FVM remains responsible for selecting and installing the Flutter SDK declared by `.fvmrc`; the shell does not introduce a second Flutter version source.
- **R2 — Direnv:** Add a root `.envrc` containing `use nix` so direnv loads `shell.nix` automatically.
- **R3 — Just recipes:** Add a root `justfile` with a discoverable default recipe and common Flutter/Dart workflows. Recipes that invoke Flutter or Dart must invoke them through `fvm`, including dependency setup, formatting, analysis, tests, code generation, running, cleaning, and building.
- **R4 — Agent guidance:** Add a development-workflow guide under `.trellis/spec/guides/`, register it in the guide index, and add a concise root `AGENTS.md` pointer so agents find the Nix/FVM/Just contract before changing code.
- **R5 — Existing behavior:** Do not modify application Dart code, generated sources, dependency versions, platform projects, or CI workflows.

## Acceptance Criteria

- [x] `nix-shell --run 'command -v just && command -v fvm'` succeeds from the repository root and both commands resolve inside the Nix shell.
- [x] `.envrc` is exactly the minimal `use nix` integration required for direnv to load the root shell.
- [x] `just --list` shows the documented development recipes, and the recipes use FVM-prefixed Flutter/Dart commands.
- [x] The guide explains first-time setup, the pinned Flutter source, the standard `just` commands, and the boundary between repository tooling and platform SDK prerequisites.
- [x] The guide index and root `AGENTS.md` make the guide discoverable to future agents.
- [x] Nix evaluation and Just parsing/dry-runs succeed without changing application sources.

## Out of Scope

- Pinning a nixpkgs revision or migrating the repository to a flake.
- Installing or packaging platform SDKs, Android/iOS signing material, or native desktop dependencies.
- Rewriting CI workflows to use FVM or Nix.
- Adding new application tests or changing generated output.
