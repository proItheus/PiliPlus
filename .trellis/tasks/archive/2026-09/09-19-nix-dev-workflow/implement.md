# Implementation Plan

## Ordered Changes

1. Add `shell.nix` with Nixpkgs `just` and `fvm` packages.
2. Add `.envrc` with the requested `use nix` directive.
3. Add the root `justfile` with the recipe contract in `design.md`; keep all Flutter/Dart calls behind FVM.
4. Add the canonical development workflow guide under `.trellis/spec/guides/`.
5. Register the guide in `.trellis/spec/guides/index.md`.
6. Add the root `AGENTS.md` discoverability pointer outside the managed Trellis block.
7. Inspect the diff for scope leaks and validate the Nix expression, shell command resolution, justfile parsing/listing, dry-runs, and documentation links.

## Validation Commands

```sh
nix-instantiate --eval shell.nix
nix-shell --run 'command -v just && command -v fvm && just --version && fvm --version'
just --list
just --dry-run format-check
just --dry-run analyze
just --dry-run test
just --dry-run check
just --dry-run run
just --dry-run build
just --fmt --check
```

Do not run recipes that download the Flutter SDK or invoke platform builds unless needed for a smoke test; the requested change is tooling/documentation and does not require modifying the Dart workspace.

## Risk Points

- `fvm` must be a Nixpkgs attribute on the target platform; verify it before claiming the shell is usable.
- Variadic just recipes must preserve optional Flutter arguments; verify their dry-run output.
- Documentation must state that `direnv allow` is a local trust action and that Android/iOS/desktop SDK prerequisites are not provided by this shell.

## Review Gate

Before activating the task, confirm that `prd.md`, `design.md`, and this plan contain no unresolved product decisions and that the requested files are limited to repository tooling and agent guidance. After implementation, run the checks above and leave application sources untouched.
