# Contributing to ContainerMenuBar

Thanks for your interest in improving ContainerMenuBar! This document explains
how to set up, what we expect in a change, and how to get it merged.

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

```sh
git clone https://github.com/hurryingauto3/container-mb.git
cd container-mb
make build        # swift build
make test         # swift run ContainerCoreSmokeTests
make run          # build and launch the app
```

You need a Swift 5.9+ toolchain (Xcode 15+ or the Command Line Tools) and, to
exercise the app against real data, Apple's `container` CLI
(`container system start`).

## Project layout & rules

The architecture is documented in [CLAUDE.md](CLAUDE.md). A few rules the CI and
reviewers enforce:

- **`ContainerCore` stays UI-free** — no `AppKit`/`SwiftUI` imports. It must
  remain testable headless.
- **All public model/state types are `Equatable` + `Sendable`**; cross-actor
  protocols are `Sendable`. Preserve this when adding types.
- **All CLI interaction goes through the `ContainerCLIClient` protocol** and all
  subprocess behavior through `ProcessRunning`, so both can be mocked.
- **Parsing changes live in `ContainerJSONMapper`** (add a key alias / fallback),
  not in the view layer.
- **Tests are fixture-driven** — paste representative CLI JSON and assert the
  mapped model (see `Sources/ContainerCoreSmokeTests/main.swift`).
- **Every source file carries an SPDX header**: `// SPDX-License-Identifier: Apache-2.0`.

## Coding style

We use [SwiftLint](https://github.com/realm/swiftlint). Install it
(`brew install swiftlint`) and run it before pushing:

```sh
swiftlint
```

Match the surrounding code's naming, comment density, and idioms.

## Making a change

1. Fork and create a topic branch (`fix/...`, `feat/...`).
2. Make focused commits with clear messages (imperative mood). Conventional
   Commit prefixes (`feat:`, `fix:`, `docs:`) are welcome but not required.
3. Add or update tests for any behavior change. `make test` must pass.
4. Update [CHANGELOG.md](CHANGELOG.md) under the `Unreleased` section.
5. Open a pull request and fill in the template. CI (build, tests, lint) must be
   green.

## Reporting bugs & requesting features

Use the GitHub issue templates. For security issues, **do not** open a public
issue — follow [SECURITY.md](SECURITY.md).

## Releasing (maintainers)

1. Bump `marketing` in `Sources/ContainerCore/AppVersion.swift`.
2. Move the `Unreleased` CHANGELOG entries under a new version heading with the date.
3. Commit, then tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. The release workflow builds, signs/notarizes (when secrets are set), and
   attaches `ContainerMenuBar-X.Y.Z.dmg` to a new GitHub Release.
