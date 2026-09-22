# Document CI build and artifact download

## Goal

Give future agents a repository-backed procedure for building the macOS app on GitHub Actions and downloading the resulting DMG locally.

## Confirmed repository facts

- `.github/workflows/mac.yml` supports `workflow_dispatch`, runs on `macos-26`, builds the release app, creates a DMG, and uploads it with `actions/upload-artifact@v7` using `archive: false`.
- The macOS workflow is the narrowest build path. It accepts `--ref <branch>` through `gh workflow run`; the pushed ref must contain the changes being built.
- With `archive: false`, the uploaded artifact is the raw DMG. `gh run download` expects a ZIP archive and cannot extract this artifact; download it through the artifact API instead.
- The artifact API exposes the artifact ID, raw filename, size, and SHA-256 digest. `gh api --silent` suppresses the binary body and must not be used for the raw download.

## Requirements

- Add a CI macOS build section to `.trellis/spec/guides/development-workflow.md`.
- Document prerequisites: authenticated `gh`, repository/ref selection, and pushing the target branch before dispatch.
- Document the exact trigger and wait commands, including how to capture the run ID and inspect failed logs.
- Document artifact discovery with `gh api`, raw DMG download through `/actions/artifacts/<artifact-id>/zip`, use of `$TMPDIR`, optional copying to `~/Downloads`, and checksum verification.
- Explain the `archive: false` behavior and the failed `gh run download` path so future agents do not repeat it.
- Keep the procedure generic for future branches and do not embed the prior run's version, artifact ID, or local path.

## Acceptance Criteria

- [x] A future agent can push a chosen branch, dispatch only the macOS workflow, wait for completion, and identify the run URL from the documented commands.
- [x] A future agent can diagnose a failed run using the documented failed-log command.
- [x] A future agent can list the run's artifact ID/name/digest and download the raw DMG without `gh run download`.
- [x] The instructions verify the local file size/type and SHA-256 digest against GitHub's artifact metadata.
- [x] The guide states the macOS workflow's runner/build/upload behavior and the scope boundary remains documentation-only.

## Scope boundary

Change only `.trellis/spec/guides/development-workflow.md` and this task artifact. Do not change GitHub workflow behavior, add a Just recipe, modify application code, or commit a release artifact.
