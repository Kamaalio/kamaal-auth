# KamaalAuth Repository Guide

## Pull requests

- Keep one commit per pull request. Fold follow-up fixes and documentation
  into that commit before updating the PR branch. Check the remote head before
  any history rewrite, and use a lease protected push.

## Swift snapshot failures in CI

- Run `just` at the repository root to see the available recipes. Use
  `just test-swift` for the macOS and iOS suites; its iOS recipe uses
  `scripts/with-ios-simulator-lock` to serialize simulator access.
- When the Swift test job fails, check the `swift-snapshot-failures` artifact
  on that GitHub Actions run. The workflow uploads it only on failure and
  logs the runner's macOS version with `sw_vers -productVersion`.
- The collection step currently targets
  `AuthSignInScreenFocusedFieldSnapshotTests`. It copies failure PNGs from
  the macOS temporary directory and the iOS simulator's `data/tmp` directory.
  Missing iOS 26 references may also be recorded directly under
  `Tests/KamaalAuthUITests/__Snapshots__/AuthSignInScreenFocusedFieldSnapshotTests/`;
  those PNGs are collected too.
- Download and inspect the actual PNGs before updating references. Check that
  the focused field is visible in the compact viewport and that the light
  and dark appearances are correct. A failing image can reveal a behavior or
  timing bug; fix that first instead of accepting the image as a baseline.
- Match the reference name to the runner's OS version, then rerun CI after
  committing reviewed references. If you add another snapshot suite, update
  the collection paths in `.github/workflows/main.yaml` so its failures are
  included in the artifact.
