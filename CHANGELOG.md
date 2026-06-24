# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-06-24

### Added

- App icon: a material-style isometric 3D box, generated reproducibly by
  `Scripts/generate-icon.swift` and bundled into the app.
- DMG installer (`make dmg` / `Scripts/make-dmg.sh`) with a drag-to-Applications
  layout and volume icon; this is now the primary download.
- Release workflow signs with Developer ID and notarizes + staples the DMG when
  the relevant repository secrets are present (ad-hoc otherwise).

### Changed

- Releases now ship a `.dmg` instead of a `.app.zip`.

### Removed

- The `curl | bash` one-line installer (`Scripts/install.sh`), in favor of the
  DMG.

## [1.0.0] - 2026-06-24

### Added

- Read-only menu-bar dashboard for the Apple `container` runtime: containers,
  volumes, and networks behind a segmented section switcher.
- Container detail: live CPU %, memory, network/block I/O, process count,
  published ports, command, resource limits, networks, IP addresses, mounts, and
  labels.
- Volume detail (driver, format, size, source) and network detail (mode, subnet,
  gateway, plugin).
- Versioning system: a single source of truth in `AppVersion.swift` that feeds
  the bundle version, the in-app header, and the release tag.
- `make install` to install the app bundle into `/Applications`; packaging now
  ad-hoc signs the bundle with the hardened runtime and supports a Developer ID
  via `SIGN_IDENTITY`.
- Open-source project artifacts: Apache-2.0 license, contributing guide, code of
  conduct, security policy, issue/PR templates, and CI/release workflows.

### Fixed

- App now launches reliably via an explicit `NSApplication` entry point (a bare
  `@main` on the delegate did not install it, so the UI never appeared).
- Container IP addresses now parse from `status.networks[].ipv4Address/ipv6Address`
  (CIDR suffix stripped) and are shown in the UI.
- Network subnet and volume source/driver now parse from their real locations in
  the CLI output.

### Security

- Bounded the recursion depth of JSON traversal to guard against pathological or
  hostile CLI output.

[Unreleased]: https://github.com/hurryingauto3/container-mb/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/hurryingauto3/container-mb/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hurryingauto3/container-mb/releases/tag/v1.0.0
