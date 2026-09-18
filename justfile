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
