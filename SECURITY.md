# Security Policy

## Supported versions

This project is pre-1.x in spirit and ships from `main`. Security fixes are
applied to the latest released version and `main`.

| Version | Supported |
| ------- | --------- |
| latest release / `main` | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Report privately via GitHub's
[private vulnerability reporting](https://github.com/hurryingauto3/container-mb/security/advisories/new)
(Security → Advisories → Report a vulnerability), or email **ah7072@nyu.edu**
with the details and reproduction steps.

We aim to acknowledge reports within 5 business days and to provide a fix or
mitigation timeline after triage. Please give us a reasonable window to address
the issue before any public disclosure.

## Security model

ContainerMenuBar is intentionally **read-only**: it runs a fixed set of
non-mutating `container` subcommands (`list`, `stats`, `inspect`,
`network list`, `volume list`, `system status`, `--version`). It does not:

- run a privileged or background helper service,
- accept network input, or
- write to the `container` runtime.

Arguments are passed to the subprocess as an argument vector (no shell
interpretation), and CLI JSON is treated as untrusted and parsed defensively
with a bounded-depth traversal.

### Binary resolution

The app executes the `container` binary it finds, probing trusted absolute
locations first (`/usr/local/bin`, `/opt/homebrew/bin`, `/usr/bin`) and falling
back to `PATH`. On a shared or misconfigured machine, an attacker who can place
a binary named `container` earlier in your `PATH`, or who can write to those
directories, could have their binary executed by this app (the same exposure as
running `container` yourself). Keep those directories and your `PATH` trusted.

## Installing safely

Releases are distributed as a `.dmg`. When a build is **Developer ID-signed and
notarized**, it opens with a normal double-click. If a build is only **ad-hoc
signed** (no notarization), macOS Gatekeeper warns on first launch — right-click
the app → **Open** → **Open**.

To verify a download:

```sh
# Inside the mounted DMG, or after copying to /Applications:
codesign --verify --strict --verbose=2 /Applications/ContainerMenuBar.app
spctl --assess --type execute --verbose /Applications/ContainerMenuBar.app
```

Only download release assets from the official
[Releases page](https://github.com/hurryingauto3/container-mb/releases). Building
from source (`make install`) gives you full provenance.

### Enabling notarized release builds (maintainers)

The release workflow produces a Developer ID-signed, notarized, stapled DMG when
these repository secrets are set (otherwise it falls back to an ad-hoc DMG):

| Secret | Purpose |
| ------ | ------- |
| `MACOS_CERTIFICATE_BASE64` | base64 of the Developer ID Application certificate (`.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_PASSWORD` | app-specific password for that Apple ID |
| `APPLE_TEAM_ID` | your Apple Developer Team ID |

All of these require a paid Apple Developer account.
