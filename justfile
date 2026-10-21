default:
    @just --list

# Install the Flutter SDK selected by .fvmrc and fetch Dart packages.
setup:
    fvm install
    fvm flutter pub get

# Fetch Dart packages without reinstalling the FVM-managed Flutter SDK.
deps:
    fvm flutter pub get

# Format application, test, and tooling Dart code.
format:
    fvm dart format lib test tool

# Check formatting without changing files.
format-check:
    fvm dart format --output=none --set-exit-if-changed lib test tool

# Analyze the Flutter project.
analyze:
    fvm flutter analyze

# Run Flutter tests, optionally passing test arguments.
test *args:
    fvm flutter test {{ args }}

# Run formatting, analysis, and tests in sequence.
check:
    just format-check
    just analyze
    just test

# Regenerate builders and replace conflicting generated outputs.
codegen:
    fvm dart run build_runner build --delete-conflicting-outputs

# Regenerate JNI bindings from the repository entrypoint.
jnigen:
    fvm dart run tool/jnigen.dart

# Run the application, optionally passing Flutter arguments.
run *args:
    fvm flutter run {{ args }}

# Build an APK by default; optionally choose a target and pass build arguments.
build target="apk" *args:
    fvm flutter build {{ target }} {{ args }}

# Remove Flutter build artifacts.
clean:
    fvm flutter clean

ci_remote := "fork"
ci_repo := "proItheus/PiliPlus"

# Push the current branch to the fork for CI.
ci-push:
    git push {{ ci_remote }} $(git branch --show-current)

# Dispatch the Android build workflow on CI.
ci-build-android:
    gh workflow run build.yml --repo {{ ci_repo }} --ref $(git branch --show-current) \
        -f build_android=true -f build_ios=false -f build_mac=false \
        -f build_win_x64=false -f build_linux_x64=false

# Dispatch the macOS build workflow on CI.
ci-build-mac:
    gh workflow run mac.yml --repo {{ ci_repo }} --ref $(git branch --show-current)

# Dispatch the macOS debug build workflow on CI (PILI_DIAG probe).
ci-build-mac-debug:
    git push {{ ci_remote }} $(git branch --show-current)
    gh workflow run mac.yml --repo {{ ci_repo }} --ref $(git branch --show-current) \
        -f build_mode=debug

# Push to CI and dispatch both the Android and macOS builds.
ci-build: ci-push ci-build-android ci-build-mac
