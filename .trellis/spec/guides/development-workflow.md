# Development workflow

This repository keeps the Flutter SDK selection in FVM and the command-line workflow in Nix and Just. The checked-in `.fvmrc` selects Flutter `3.47.4`; do not add another Flutter SDK source to the Nix shell.

## Entering the environment

Install Nix and direnv using your operating system's package manager, then allow this repository once:

```sh
direnv allow
```

The root `.envrc` contains only `use nix`, so direnv evaluates `shell.nix` and puts Nixpkgs `just` and `fvm` on `PATH`. If direnv is not enabled, enter the same environment explicitly with `nix-shell` from the repository root. `direnv allow` is a local trust decision: review the `.envrc` before allowing it.

On first use, install the FVM-selected Flutter SDK and fetch packages:

```sh
just setup
```

`setup` runs `fvm install` using `.fvmrc`, followed by `fvm flutter pub get`. Use `just deps` for later dependency fetches when the SDK is already installed. Every Flutter and Dart command in the Just workflow goes through `fvm`, so run these recipes from the Nix/direnv environment rather than calling a separate global Flutter installation.

## Standard recipes

Run `just` or `just --list` to discover the available recipes:

| Recipe | Purpose |
|---|---|
| `just setup` | Install the `.fvmrc` Flutter SDK and fetch packages |
| `just deps` | Fetch Dart packages |
| `just format` | Format `lib`, `test`, and `tool` |
| `just format-check` | Verify formatting without writing files |
| `just analyze` | Run Flutter analysis |
| `just test` | Run the Flutter test suite |
| `just check` | Run format check, analysis, and tests |
| `just codegen` | Run `build_runner` and replace conflicting generated output |
| `just jnigen` | Regenerate JNI bindings with `tool/jnigen.dart` |
| `just run` | Start the Flutter application |
| `just build` | Build an APK by default |
| `just clean` | Remove Flutter build artifacts |

`test`, `run`, and `build` preserve optional arguments. For example:

```sh
just test test/account_test.dart
just test --name "loads subscriptions"
just run -d macos
just build                       # equivalent to: fvm flutter build apk
just build apk --release
just build appbundle --release
```

The first argument to `build` selects the Flutter build target and defaults to `apk`; remaining arguments are passed to Flutter. Recipes intentionally do not encode platform-specific flags.

## Agent contract

### 1. Scope / trigger

This contract applies to repository setup, dependency, formatting, analysis, test, generation, run, clean, and build work. It keeps command versions consistent without changing application code.

### 2. Signatures

- `shell.nix`: `nix-shell` environment exposing `just` and `fvm`.
- `.envrc`: `use nix`, which loads the root `shell.nix` through direnv.
- Flutter/Dart recipes: `fvm <flutter|dart> ...`, with `test`, `run`, and `build` forwarding optional arguments.

### 3. Contracts

- `.fvmrc` is the single Flutter SDK selector; the current project version is `3.47.4`.
- Nix supplies only `just` and `fvm`; platform SDKs and signing credentials stay on the host.
- `build` defaults to the `apk` target; its first argument selects another Flutter target.

### 4. Validation and error matrix

| Condition | Expected action |
|---|---|
| `just` or `fvm` is not on `PATH` | Enter the root `nix-shell` or allow direnv; do not use an unrelated global Flutter command. |
| Direnv is unavailable or not trusted | Run `nix-shell` explicitly, after reviewing `.envrc`. |
| A platform SDK/device/signing prerequisite is missing | Fix the host platform setup; do not add credentials or native SDKs to this shell. |
| Just formatting validation is needed | Run `just --fmt --check`; `just --check` alone is not the formatting check for the installed Just CLI. |

### 5. Good, base, and bad cases

- Good: `just setup`, then `just analyze` or `just test test/account_test.dart`.
- Base: `nix-shell --run 'just --list'` on a host without direnv.
- Bad: invoking `flutter`, `dart`, or `just --check` outside the documented contract.

### 6. Required verification

For changes to this workflow, verify Nix evaluation, `just`/`fvm` command resolution, `just --list`, `just --fmt --check`, and dry-runs for changed recipes. Tooling-only changes do not require downloading Flutter or running the application test suite.

### 7. Wrong versus correct

```sh
# Wrong: bypasses the repository's SDK selector.
flutter analyze

# Correct: uses the FVM SDK selected by .fvmrc.
fvm flutter analyze
```

## Platform prerequisites

Nix supplies only the repository command-line tools (`just` and `fvm`). FVM downloads the Flutter SDK selected by `.fvmrc`; it does not replace native platform toolchains. Android builds/runs still require the Android SDK, accepted licenses, an available emulator or device, and any project-specific signing material. iOS and macOS require Xcode, its command-line tools, and provisioning/signing setup. Linux and Windows desktop targets require their respective native compilers, libraries, and SDKs. Configure those prerequisites separately on the host; do not add them to this shell or commit credentials.
